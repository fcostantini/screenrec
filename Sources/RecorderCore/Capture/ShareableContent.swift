import ScreenCaptureKit

extension SCShareableContent {
    /// The one enumeration the engine binds against and `CapturableApps` lists from — shared
    /// so "listed ⇒ bindable" stays structural (docs/02 §1a). (Named to avoid SCK's own
    /// `current` property, whose flags differ.)
    static func forCapture() async throws -> SCShareableContent {
        try await excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}

extension SCStreamConfiguration {
    /// The one home of the audio-capture contract (docs/02 §1): 48 kHz stereo system audio when
    /// asked for (optional since M16-T3, ADR-019), own audio excluded, and — when given — an
    /// explicit mic device (a nil/default sentinel pins silently, docs/02 §1). Shared by the
    /// engine's primary stream and the mic rescue.
    func applyAudioCapture(systemAudio: Bool, microphoneID: String?) {
        capturesAudio = systemAudio
        sampleRate = 48_000
        channelCount = 2
        excludesCurrentProcessAudio = true
        if let microphoneID {
            captureMicrophone = true
            microphoneCaptureDeviceID = microphoneID
        }
    }
}
