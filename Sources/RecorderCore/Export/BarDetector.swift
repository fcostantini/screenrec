import AVFoundation
import CoreGraphics
import Foundation

/// Finds the letterbox bars a stream capture arrives with (M26-T3), so a crop can be offered
/// instead of dragged.
///
/// A bar is a run of lines that touch a frame edge, are flat along their length, and agree with each
/// other in level. ⚠️ **What the level is never enters into it:** bars encoded at luma 64 decode to
/// 73 (measured, docs/07), so the "black-ish, luma 62–66" test this was filed on would miss its own
/// fixture. Flatness and edge-anchoring are the signal.
public enum BarDetector {
    /// How far a line may vary along its length, and from the bar's level, and still count as flat.
    /// Measured on HEVC-compressed bars: at 6 the run stops 6 px short of the boundary (ringing
    /// makes a bar's last rows noisier than its middle), and at 16 the frames of one clip disagree
    /// by up to 4 px — which the conservative combine below then inherits. **At 24 every frame lands
    /// on the boundary exactly**, and no negative fires below 32 (docs/07). ⚠️ Calibrated on a
    /// synthetic letterbox — re-run it against a real capture before treating it as settled.
    public static let defaultTolerance = 24.0

    /// The crop `image` implies, or nil when nothing edge-anchored is flat enough to be a bar.
    public static func bars(in image: CGImage, tolerance: Double = defaultTolerance) -> CropRect? {
        guard let frame = Frame(image) else { return nil }
        let top = frame.run(from: .top, tolerance: tolerance)
        let bottom = frame.run(from: .bottom, tolerance: tolerance)
        let left = frame.run(from: .left, tolerance: tolerance)
        let right = frame.run(from: .right, tolerance: tolerance)
        return crop(
            top: top, bottom: bottom, left: left, right: right,
            width: frame.width, height: frame.height)
    }

    /// The crop every frame agrees on: the **smallest** bar any of them shows. A dark scene reads
    /// like a bar, so taking the most conservative answer means one misleading frame can only
    /// under-crop — never eat content. Nil unless they all see something.
    public static func bars(in images: [CGImage], tolerance: Double = defaultTolerance) -> CropRect? {
        guard let first = images.first, let reference = Frame(first) else { return nil }
        var top = Int.max, bottom = Int.max, left = Int.max, right = Int.max
        for image in images {
            guard let frame = Frame(image),
                frame.width == reference.width, frame.height == reference.height
            else { continue }
            top = min(top, frame.run(from: .top, tolerance: tolerance))
            bottom = min(bottom, frame.run(from: .bottom, tolerance: tolerance))
            left = min(left, frame.run(from: .left, tolerance: tolerance))
            right = min(right, frame.run(from: .right, tolerance: tolerance))
        }
        guard top < Int.max else { return nil }
        return crop(
            top: top, bottom: bottom, left: left, right: right,
            width: reference.width, height: reference.height)
    }

    /// Samples `frames` across `url` and returns the crop they agree on. Decoding is
    /// `FilmstripThumbnails`' random-access seek (M24-T4), at the source's own size so the rect is
    /// already in source pixels — its cost tracks keyframe spacing × count, not the take's length.
    public static func detect(
        in url: URL, frames: Int = 5, tolerance: Double = defaultTolerance
    ) async throws -> CropRect? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        let times = FilmstripThumbnails.times(count: frames, duration: duration)
        guard !times.isEmpty else { return nil }

        var images: [CGImage] = []
        for await frame in FilmstripThumbnails.stream(
            for: asset, times: times,
            maxPixels: Int(max(size.width, size.height).rounded()))
        {
            images.append(frame.image)
        }
        return bars(in: images, tolerance: tolerance)
    }

    /// The rect those four runs leave, refusing the degenerate readings: a frame with no bars at
    /// all, and a frame flat enough that the "bars" swallow it (a fade to black is not a letterbox).
    private static func crop(
        top: Int, bottom: Int, left: Int, right: Int, width: Int, height: Int
    ) -> CropRect? {
        guard top > 0 || bottom > 0 || left > 0 || right > 0 else { return nil }
        let keptWidth = width - left - right
        let keptHeight = height - top - bottom
        guard keptWidth >= minimumKept, keptHeight >= minimumKept else { return nil }
        return CropRect(x: left, y: top, width: keptWidth, height: keptHeight)
    }

    /// Below this the reading is noise, not a crop anyone wants.
    private static let minimumKept = 16
}

/// One decoded frame, as luma sampled along rows and columns. Every fourth pixel: a bar is a
/// property of a whole line, and sampling costs a quarter of the reads.
private struct Frame {
    enum Edge { case top, bottom, left, right }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// How many lines of a bar sit against `edge`: the first must be flat, and each one after it
    /// must be flat *and* at the same level.
    func run(from edge: Edge, tolerance: Double) -> Int {
        let horizontal = edge == .top || edge == .bottom
        let limit = (horizontal ? height : width) / 2  // a bar past half the frame isn't one
        let start = (edge == .top || edge == .left) ? 0 : (horizontal ? height : width) - 1
        let step = (edge == .top || edge == .left) ? 1 : -1

        let first = line(at: start, horizontal: horizontal)
        guard first.spread <= tolerance else { return 0 }
        var count = 0
        var index = start
        while count < limit {
            let stats = line(at: index, horizontal: horizontal)
            guard stats.spread <= tolerance, abs(stats.mean - first.mean) <= tolerance else { break }
            count += 1
            index += step
        }
        return count
    }

    /// Mean and range of luma along one row or column.
    private func line(at index: Int, horizontal: Bool) -> (mean: Double, spread: Double) {
        var sum = 0.0, lowest = 255.0, highest = 0.0, count = 0
        for other in stride(from: 0, to: horizontal ? width : height, by: 4) {
            let value = luma(horizontal ? other : index, horizontal ? index : other)
            sum += value
            lowest = min(lowest, value)
            highest = max(highest, value)
            count += 1
        }
        guard count > 0 else { return (0, .infinity) }
        return (sum / Double(count), highest - lowest)
    }

    private func luma(_ x: Int, _ y: Int) -> Double {
        let offset = (y * width + x) * 4
        return 0.2126 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1])
            + 0.0722 * Double(bytes[offset + 2])
    }
}
