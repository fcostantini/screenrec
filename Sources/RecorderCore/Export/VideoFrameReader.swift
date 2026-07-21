import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Reads a clip's video as already-scaled, fixed-fps `CGImage`s — the frame source a GIF (or any
/// per-frame consumer) needs. An `AVAssetReader` video composition does the scaling (`renderSize`);
/// the fps cap is a PTS subsample in `readFrames`, because `AVAssetReaderVideoCompositionOutput`
/// emits one frame per source frame and ignores `frameDuration` for the output rate. This is
/// M10-T1's `AVAssetReader` read side, adapted to CFR (T1's own path stays VFR for the transcode).
struct VideoFrameReader {
    enum ReaderError: Error, Equatable {
        case noVideoTrack
        case unreadable(String)
        case readFailed(String)
    }

    /// The emitted frame size (fitted, even), the per-frame delay in seconds (1/fps), and the full
    /// source duration (so a consumer can tell it was capped without loading the asset again).
    let size: (width: Int, height: Int)
    let frameDuration: Double
    let sourceSeconds: Double

    private let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput

    private init(
        size: (width: Int, height: Int), frameDuration: Double, sourceSeconds: Double,
        reader: AVAssetReader, output: AVAssetReaderVideoCompositionOutput
    ) {
        self.size = size
        self.frameDuration = frameDuration
        self.sourceSeconds = sourceSeconds
        self.reader = reader
        self.output = output
    }

    /// Builds a reader over the first `maxSeconds` of `input`, frames fitted within
    /// `maxWidth × maxHeight` and emitted at `fps`. Does the async property loads; `readFrames`
    /// then blocks.
    static func make(
        input: URL, maxWidth: Int, maxHeight: Int, fps: Int, maxSeconds: Double
    ) async throws -> VideoFrameReader {
        let asset = AVURLAsset(url: input)
        let videoTrack: AVAssetTrack
        let duration: CMTime
        let naturalSize: CGSize
        do {
            guard let track = try await asset.load(.tracks).first(where: { $0.mediaType == .video })
            else { throw ReaderError.noVideoTrack }
            videoTrack = track
            duration = try await asset.load(.duration)
            naturalSize = try await videoTrack.load(.naturalSize)
        } catch let error as ReaderError {
            throw error
        } catch {
            throw ReaderError.unreadable(
                "Couldn't read “\(input.lastPathComponent)”. \(error.localizedDescription)")
        }

        let size = Exporter.fittedSize(
            width: Int(naturalSize.width.rounded()), height: Int(naturalSize.height.rounded()),
            maxWidth: maxWidth, maxHeight: maxHeight)

        do {
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTimeMinimum(
                    duration, CMTime(seconds: maxSeconds, preferredTimescale: 600)))

            // The composition scales every frame to `renderSize`; the fps subsample happens in
            // `readFrames`, not here (see the type doc).
            let composition = try await AVMutableVideoComposition.videoComposition(
                withPropertiesOf: asset)
            composition.renderSize = CGSize(width: size.width, height: size.height)

            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack],
                videoSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
            output.videoComposition = composition
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw ReaderError.readFailed("The reader refused the video track.")
            }
            reader.add(output)

            return VideoFrameReader(
                size: size, frameDuration: 1.0 / Double(fps), sourceSeconds: duration.seconds,
                reader: reader, output: output)
        } catch let error as ReaderError {
            throw error
        } catch {
            throw ReaderError.readFailed(error.localizedDescription)
        }
    }

    /// Feeds frames to `handle` in order at the target fps, blocking until the clip is exhausted: a
    /// frame is kept only once at least `frameDuration` has passed since the last kept one (the
    /// cadence advances only on an emitted frame, so a skip leaves no gap). Frames aren't retained
    /// past the call, so the reader's pool never stalls. Run off the main actor.
    func readFrames(_ handle: (CGImage) throws -> Void) throws {
        guard reader.startReading() else {
            throw ReaderError.readFailed(
                reader.error?.localizedDescription ?? "The reader couldn't start.")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }  // prompt release on throw

        let interval = CMTime(seconds: frameDuration, preferredTimescale: 600)
        var nextKeep = CMTime.negativeInfinity  // keep the first frame
        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard CMTimeCompare(pts, nextKeep) >= 0 else { continue }
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
            guard let image else { continue }  // don't advance the cadence on a failed convert
            nextKeep = CMTimeAdd(pts, interval)
            try handle(image)
        }
        guard reader.status != .failed else {
            throw ReaderError.readFailed(
                reader.error?.localizedDescription ?? "Reading the clip failed.")
        }
    }
}
