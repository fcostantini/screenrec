import AVFoundation
import CoreMedia
import Foundation

/// The one place a crop becomes an `AVVideoComposition`: the share export renders it through an
/// asset reader (M26-T1) and the precise trim through an `AVAssetExportSession` (M26-T4), and the
/// transform must be the same one in both.
enum CropComposition {
    /// Renders `crop` of `videoTrack` into a `target`-sized frame, crop and fit in one transform.
    /// The layer transform's origin is the frame's top-left (measured, docs/07). Per-axis scale,
    /// because `fittedSize` rounds each dimension to even independently and one shared scale would
    /// leave an unpainted edge of up to a pixel. Assumes an identity `preferredTransform`, true of
    /// every file this app writes.
    ///
    /// `base` is the caller's, because frame timing does not travel with the crop: an
    /// `AVAssetExportSession` honours `frameDuration` and `sourceTrackIDForFrameTiming`, so a base
    /// built by `videoComposition(withPropertiesOf:)` keeps a capture variable-rate — measured at
    /// 2.9× fewer bytes than a hand-built 1/60 base. A reader ignores both.
    static func make(
        cropping crop: CropRect,
        of videoTrack: AVAssetTrack,
        to target: (width: Int, height: Int),
        duration: CMTime,
        onto base: AVMutableVideoComposition
    ) -> AVMutableVideoComposition {
        let scaleX = Double(target.width) / Double(crop.width)
        let scaleY = Double(target.height) / Double(crop.height)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(
            CGAffineTransform(scaleX: scaleX, y: scaleY).concatenating(
                CGAffineTransform(
                    translationX: -Double(crop.x) * scaleX, y: -Double(crop.y) * scaleY)),
            at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]

        base.renderSize = CGSize(width: target.width, height: target.height)
        base.instructions = [instruction]
        return base
    }

    /// A base for a path that does its own frame timing. `frameDuration` is never read there but
    /// must be valid, or the reader refuses the composition.
    static func readerBase() -> AVMutableVideoComposition {
        let base = AVMutableVideoComposition()
        base.frameDuration = CMTime(value: 1, timescale: 60)
        return base
    }
}
