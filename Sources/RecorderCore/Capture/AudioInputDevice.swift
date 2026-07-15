import AVFoundation

/// A selectable audio input, decoupled from AVFoundation so the CLI and app can present
/// devices without importing AVFoundation themselves.
public struct AudioInputDevice: Sendable, Equatable {
    public let uniqueID: String
    public let name: String
    public let isDefault: Bool

    public init(uniqueID: String, name: String, isDefault: Bool) {
        self.uniqueID = uniqueID
        self.name = name
        self.isDefault = isDefault
    }
}

public enum AudioInputs {
    /// Currently-connected audio input devices, the system default marked.
    public static func available() -> [AudioInputDevice] {
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
        return devices.map {
            AudioInputDevice(uniqueID: $0.uniqueID, name: $0.localizedName, isDefault: $0.uniqueID == defaultID)
        }
    }
}
