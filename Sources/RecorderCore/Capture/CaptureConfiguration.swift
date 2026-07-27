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

/// What the stream captures. `.app` composites one app's windows (and scopes system audio to
/// that app — measured, docs/02 §1a) on the main display; frames stay display-sized, so
/// bitrate/timing math is content-independent. `.region` crops one display to a fixed screen
/// rectangle (docs/02 §1b); frames are the region's size, so the output is smaller. `.window`
/// captures one window independently of any display (docs/02 §1c); frames are the window's size.
public enum ContentSelection: Sendable, Equatable {
    case display(DisplaySelection)
    case app(bundleID: String)
    /// `rect` is in the display's **points**, top-left origin (SCK `sourceRect` space, docs/02
    /// §1b) — not AppKit's bottom-left screen points. The engine clamps it to the display and
    /// fails loud if it doesn't overlap.
    case region(display: DisplaySelection, rect: CGRect)
    /// An `SCWindow.windowID`, resolved against the shareable content at start time. The id is
    /// not stable across a relaunch of the owning app (measured: one window went 1498 → 1512), and
    /// ids are **reused** — so `ownerBundleID`, when given, is checked against the resolved
    /// window's owner and a mismatch fails loud. A stored pick must pass it; a freshly-listed id
    /// (the CLI, which lists and binds in one breath) passes nil.
    case window(id: CGWindowID, ownerBundleID: String?)
}

/// Which device a lost microphone recovers onto (docs/03 M8-T2: honor the pick).
public enum MicrophoneRecovery: Sendable, Equatable {
    /// A specific pick rebinds only itself — never silently substitutes another device.
    case sameDevice
    /// Automatic (M6-T13) follows the CURRENT system default at return time.
    case systemDefault
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
    public var content: ContentSelection
    public var microphone: MicrophoneSelection
    public var microphoneRecovery: MicrophoneRecovery
    /// Whether the stream captures what the Mac is playing (ADR-019). Off records screen + mic
    /// only; off with `.none` mic is a legitimate silent recording.
    public var capturesSystemAudio: Bool
    public var frameRateCap: Int
    public var quality: QualityPreset

    public init(
        content: ContentSelection = .display(.main),
        microphone: MicrophoneSelection = .none,
        microphoneRecovery: MicrophoneRecovery = .sameDevice,
        capturesSystemAudio: Bool = true,
        frameRateCap: Int = 60,
        quality: QualityPreset = .balanced
    ) {
        self.content = content
        self.microphone = microphone
        self.microphoneRecovery = microphoneRecovery
        self.capturesSystemAudio = capturesSystemAudio
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
