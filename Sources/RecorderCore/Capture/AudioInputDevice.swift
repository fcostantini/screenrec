import AVFoundation
import CoreAudio

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
    ///
    /// UIDs come from the CoreAudio HAL, which answers live on every call —
    /// `AVCaptureDevice.DiscoverySession` caches inside a long-running process and misses devices
    /// hot-plugged after launch. Each UID is then validated and named through `AVCaptureDevice`
    /// (live per device), so a listed device is always one the recorder's resolver can bind.
    public static func available() -> [AudioInputDevice] {
        select(
            uniqueIDs: inputDeviceUIDs(),
            defaultUID: AVCaptureDevice.default(for: .audio)?.uniqueID,
            resolveName: { AVCaptureDevice(uniqueID: $0)?.localizedName })
    }

    /// Keep the UIDs `resolveName` resolves — i.e. the recorder can bind — and mark the default.
    /// Pure: unit-tested by injecting `resolveName`, with resolvable and unresolvable UIDs on each
    /// side.
    static func select(
        uniqueIDs: [String], defaultUID: String?, resolveName: (String) -> String?
    ) -> [AudioInputDevice] {
        uniqueIDs.compactMap { uid in
            resolveName(uid).map {
                AudioInputDevice(uniqueID: uid, name: $0, isDefault: uid == defaultUID)
            }
        }
    }

    // MARK: - CoreAudio HAL (live device enumeration)

    /// UIDs of every device carrying an input stream, read live. Output-only devices never reach
    /// the UID read.
    private static func inputDeviceUIDs() -> [String] {
        deviceIDs().compactMap { hasInputStreams($0) ? deviceUID($0) : nil }
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func deviceUID(_ device: AudioObjectID) -> String? {
        var address = globalAddress(kAudioDevicePropertyDeviceUID)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String   // HAL returns a +1 CFString
    }

    static func globalAddress(
        _ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}
