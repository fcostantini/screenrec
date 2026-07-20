import ScreenCaptureKit

extension SCShareableContent {
    /// The one enumeration the engine binds against and `CapturableApps` lists from — shared
    /// so "listed ⇒ bindable" stays structural (docs/02 §1a). (Named to avoid SCK's own
    /// `current` property, whose flags differ.)
    static func forCapture() async throws -> SCShareableContent {
        try await excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}
