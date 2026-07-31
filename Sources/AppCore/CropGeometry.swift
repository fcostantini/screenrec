import CoreGraphics
import Foundation
import RecorderCore

/// Maps between a rectangle drawn on a video preview and the crop it means in source pixels
/// (M26-T2). The preview letterboxes its source — aspect-fit and centred — so a drag has to be
/// measured against the video's own rect inside the view, never the view's bounds.
public enum CropGeometry {
    /// Where the video really sits inside a `viewSize` preview.
    public static func videoRect(sourceSize: CGSize, in viewSize: CGSize) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, viewSize.width > 0, viewSize.height > 0
        else { return .zero }
        let scale = min(viewSize.width / sourceSize.width, viewSize.height / sourceSize.height)
        let fitted = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: (viewSize.width - fitted.width) / 2, y: (viewSize.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    /// The crop that `rect`, drawn in the preview's coordinates, means in source pixels — or nil
    /// when the drag missed the video or is too small to encode.
    ///
    /// Clamped to the source before validating: the pointer cannot reach outside the video, so an
    /// edge-to-edge drag that rounds a pixel past it is arithmetic, not intent. `Exporter` still
    /// refuses an out-of-bounds rect from anywhere else.
    public static func crop(
        fromViewRect rect: CGRect, sourceSize: CGSize, viewSize: CGSize
    ) -> CropRect? {
        let video = videoRect(sourceSize: sourceSize, in: viewSize)
        guard video.width > 0, video.height > 0 else { return nil }
        let drawn = rect.standardized.intersection(video)
        guard !drawn.isNull, !drawn.isEmpty else { return nil }

        let scale = sourceSize.width / video.width
        let sourceWidth = Int(sourceSize.width.rounded())
        let sourceHeight = Int(sourceSize.height.rounded())
        let x = min(max(0, Int(((drawn.minX - video.minX) * scale).rounded())), sourceWidth - 2)
        let y = min(max(0, Int(((drawn.minY - video.minY) * scale).rounded())), sourceHeight - 2)
        let width = min(Int((drawn.width * scale).rounded()), sourceWidth - x)
        let height = min(Int((drawn.height * scale).rounded()), sourceHeight - y)
        return try? Exporter.validatedCrop(
            CropRect(x: x, y: y, width: width, height: height),
            sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    /// Where `crop` sits in a `viewSize` preview — the inverse, for drawing the band back over the
    /// video. The crop itself is held in source pixels, so it survives anything the view does.
    public static func viewRect(
        for crop: CropRect, sourceSize: CGSize, viewSize: CGSize
    ) -> CGRect {
        let video = videoRect(sourceSize: sourceSize, in: viewSize)
        guard sourceSize.width > 0, video.width > 0 else { return .zero }
        let scale = video.width / sourceSize.width
        return CGRect(
            x: video.minX + Double(crop.x) * scale, y: video.minY + Double(crop.y) * scale,
            width: Double(crop.width) * scale, height: Double(crop.height) * scale)
    }
}
