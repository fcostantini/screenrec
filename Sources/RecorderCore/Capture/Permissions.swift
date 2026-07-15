import AVFoundation
import CoreGraphics
import Foundation

/// TCC / device state, normalized. `restricted` (MDM etc.) folds into `denied` — from
/// the user's side both mean "can't, and can't fix it by tapping Allow".
public enum PermissionState: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// The single verdict the UI/CLI act on before recording.
public enum RecordingReadiness: Sendable, Equatable {
    case ready
    case needsScreenRecording          // can request → prompt/onboarding
    case needsMicrophone               // can request → prompt
    case blocked(reason: String)       // user must change System Settings
}

/// Result of resolving which microphone to capture. Never `nil`: SCK's
/// `microphoneCaptureDeviceID` must be an explicit ID or capture fails with an opaque
/// "invalid parameter" (docs/02 §1).
public enum MicrophoneResolution: Sendable, Equatable {
    case explicit(String)
    case noDevice(reason: String)
}

/// Permission preflight/request and microphone resolution. Decision logic is pure and
/// injectable (unit-tested); live queries are thin wrappers over TCC / AVFoundation.
public enum Permissions {

    // MARK: - Pure decision logic (injectable, unit-tested)

    /// Maps permission states to a single readiness verdict. `microphoneRequired` is
    /// false when the user has chosen no microphone.
    public static func recordingReadiness(
        screen: PermissionState,
        microphone: PermissionState,
        microphoneRequired: Bool
    ) -> RecordingReadiness {
        switch screen {
        case .notDetermined:
            return .needsScreenRecording
        case .denied:
            return .blocked(reason: "Screen Recording is turned off for this app. Turn it on in "
                + "System Settings → Privacy & Security → Screen & System Audio Recording, then "
                + "quit and reopen the app.")
        case .granted:
            break
        }

        guard microphoneRequired else { return .ready }

        switch microphone {
        case .granted:
            return .ready
        case .notDetermined:
            return .needsMicrophone
        case .denied:
            return .blocked(reason: "Microphone access is turned off for this app. Turn it on in "
                + "System Settings → Privacy & Security → Microphone, or record without a microphone.")
        }
    }

    /// A non-empty preferred ID that still refers to a present device wins, else the injected
    /// default, else no device. A stale preferred ID (device unplugged) must not pass through:
    /// it fails capture with the opaque "invalid parameter" (docs/02 §1). `deviceExists` and
    /// `defaultDeviceID` are injected so this is testable without real hardware.
    public static func resolveMicrophoneID(
        preferred: String?,
        deviceExists: (String) -> Bool = { _ in true },
        defaultDeviceID: () -> String?
    ) -> MicrophoneResolution {
        if let preferred, !preferred.isEmpty, deviceExists(preferred) {
            return .explicit(preferred)
        }
        if let fallback = defaultDeviceID(), !fallback.isEmpty {
            return .explicit(fallback)
        }
        return .noDevice(reason: "No microphone found. Connect one, or record without a microphone.")
    }

    // MARK: - Live queries (TCC / AVFoundation)

    /// Screen Recording state. The public API cannot distinguish *denied* from
    /// not-yet-determined, so this returns `.granted` or `.notDetermined` only (docs/02 §2).
    public static func screenRecordingState() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func defaultMicrophoneID() -> String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
    }

    /// Live convenience: validate the preferred ID against currently-connected devices
    /// and resolve against the system's default input device.
    public static func resolvedMicrophoneID(preferred: String? = nil) -> MicrophoneResolution {
        resolveMicrophoneID(
            preferred: preferred,
            deviceExists: { AVCaptureDevice(uniqueID: $0) != nil },
            defaultDeviceID: defaultMicrophoneID
        )
    }
}
