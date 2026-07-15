import CoreGraphics
import Foundation

/// Recording quality tier. Raw values are the CLI/settings literals; the bitrate math
/// per tier lives in `BitrateModel`.
public enum QualityPreset: String, CaseIterable, Sendable {
    case efficient
    case balanced
    case high
}

/// Which display to capture. Resolved to a concrete `SCDisplay` by `CaptureEngine`;
/// `.main` defers to whatever is the main display at capture time.
public enum DisplaySelection: Sendable, Equatable {
    case main
    case id(CGDirectDisplayID)
}

/// Which microphone to capture. `.device` carries an already-resolved explicit
/// `uniqueID` (see `Permissions.resolveMicrophoneID`) — never a nil/default sentinel,
/// which would fail capture with the opaque "invalid parameter" (docs/02 §1).
public enum MicrophoneSelection: Sendable, Equatable {
    case none
    case device(id: String)
}

/// A complete, value-type description of what to capture. Holds no live objects — the
/// engine resolves it against `SCShareableContent` at start time.
public struct CaptureConfiguration: Sendable, Equatable {
    public var display: DisplaySelection
    public var microphone: MicrophoneSelection
    public var frameRateCap: Int
    public var quality: QualityPreset

    public init(
        display: DisplaySelection = .main,
        microphone: MicrophoneSelection = .none,
        frameRateCap: Int = 60,
        quality: QualityPreset = .balanced
    ) {
        self.display = display
        self.microphone = microphone
        self.frameRateCap = frameRateCap
        self.quality = quality
    }

    /// Pixel dimensions for a display/window: point size × backing scale factor, rounded to
    /// whole pixels. SCK wants pixels while `contentRect` is in points and `pointPixelScale` is
    /// the Retina factor (docs/02 §1); skipping this records at half resolution.
    public static func pixelDimensions(
        pointSize: CGSize,
        pointPixelScale: CGFloat
    ) -> (width: Int, height: Int) {
        (width: Int((pointSize.width * pointPixelScale).rounded()),
         height: Int((pointSize.height * pointPixelScale).rounded()))
    }
}
