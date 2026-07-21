import Foundation
import RecorderCore

/// A global shortcut combo (save-replay, or start/stop recording — M9-T4). Raw Carbon values —
/// `keyCode` is a virtual key code (kVK_*) and `modifiers` a Carbon modifier mask
/// (cmdKey/optionKey/…), because that's what `RegisterEventHotKey` takes; the app layer owns the
/// Carbon import and the display formatting.
public struct Hotkey: Sendable, Equatable {
    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌥⌘R (docs/06): the default save-replay shortcut. kVK_ANSI_R with optionKey | cmdKey.
    public static let standard = Hotkey(keyCode: 15, modifiers: 2048 | 256)

    /// ⌥⌘S: the combo seeded when the user first enables the start/stop shortcut (M9-T4).
    /// kVK_ANSI_S with optionKey | cmdKey.
    public static let recordDefault = Hotkey(keyCode: 1, modifiers: 2048 | 256)
}

/// The user's microphone pick, before resolution to a concrete device (docs/06 item 6):
/// a specific device, `automatic` (follow the system default at capture start, M6-T13), or none.
public enum MicrophonePreference: Sendable, Equatable, Hashable {
    case none
    case automatic
    case device(id: String)
}

/// The app's persisted preferences (docs/06 "Settings window").
///
/// Launch-at-login (M6) arrives with the feature it configures.
public struct Settings: Sendable, Equatable {
    public var outputDirectory: URL
    public var quality: QualityPreset
    /// docs/06 offers 30 or 60.
    public var frameRateCap: Int
    /// The microphone pick. `.device`'s uniqueID and `.automatic` are deliberately NOT validated
    /// against connected devices at load — a pick must survive its device sitting in its case;
    /// resolution happens at every stream start (and falls back to no mic).
    public var microphonePreference: MicrophonePreference
    /// The Source pick (docs/06 item 5, M7-T2): capture one app instead of the whole screen.
    /// Nil ⇒ entire screen. Not validated against running apps at load — the pick survives the
    /// app being closed; a start while it's away fails loud (never a silent whole-screen fallback).
    public var captureAppBundleID: String?
    public var replayArmed: Bool
    /// docs/06 offers 30, 60 or 120.
    public var replaySeconds: Int
    public var replayHotkey: Hotkey
    /// The optional global start/stop recording shortcut (M9-T4). Nil ⇒ off — an always-live combo
    /// the user didn't choose could silently clash, so this is opt-in.
    public var recordHotkey: Hotkey?
    /// Whether the menu-bar label shows the live elapsed clock while recording (M9-T3). Default on.
    public var showsMenuBarTimer: Bool

    public static let allowedFrameRateCaps = [30, 60]
    /// The replay buffer length range (M9-T8): 5 s floor → 15 min, seconds granularity.
    public static let replaySecondsRange = 5...900

    /// The replay length as `M:SS` for the Settings slider (M9-T8): 200 → "3:20", 5 → "0:05".
    public static func replayBufferLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    public static var standard: Settings {
        Settings(
            outputDirectory: OutputLocation.defaultDirectory(),
            quality: .balanced,
            frameRateCap: 60,
            microphonePreference: .none,
            captureAppBundleID: nil,
            replayArmed: false,
            replaySeconds: 60,
            replayHotkey: .standard,
            recordHotkey: nil,
            showsMenuBarTimer: true)
    }
}

/// Loads and saves `Settings` in `UserDefaults`.
///
/// The key names are contractual (docs/06), spelled exactly once — here. A test pins each
/// literal against the doc.
public enum SettingsStore {

    public enum Key {
        public static let outputDirectory = "outputDirectory"
        public static let qualityPreset = "qualityPreset"
        public static let fpsCap = "fpsCap"
        public static let microphoneID = "microphoneID"
        /// True ⇒ Automatic (follow the system default); a specific device lives in `microphoneID`.
        public static let microphoneAutomatic = "microphoneAutomatic"
        /// Absent ⇒ entire screen (M7-T2).
        public static let captureAppBundleID = "captureAppBundleID"
        public static let replayArmed = "replayArmed"
        public static let replaySeconds = "replaySeconds"
        public static let replayHotkey = "replayHotkey"
        /// Absent ⇒ the start/stop shortcut is off (M9-T4). Same Dict shape as `replayHotkey`.
        public static let recordHotkey = "recordHotkey"
        /// `replayHotkey`/`recordHotkey` are Dicts (docs/06): these are their inner keys.
        public static let hotkeyKeyCode = "keyCode"
        public static let hotkeyModifiers = "modifiers"
        /// Absent ⇒ on (M9-T3): the menu-bar clock is opt-out, not opt-in.
        public static let showsMenuBarTimer = "showsMenuBarTimer"
    }

    /// Reads settings, replacing anything unusable with the default.
    ///
    /// Every value is validated: unlike in-memory state, a bad persisted value is the app's
    /// problem at every launch, and the plist is user-editable. Pure over an injected
    /// `UserDefaults`, so each bad-value case is a unit test.
    public static func load(from defaults: UserDefaults) -> Settings {
        var settings = Settings.standard

        // A folder that has gone away falls back rather than poisoning every later recording
        // with an opaque "invalid parameter" (02 §2). Existence only — write access is
        // preflighted when chosen, and again at record time.
        if let path = defaults.string(forKey: Key.outputDirectory), !path.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                settings.outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        // An unknown preset means a hand-edited plist or a future version's value; the enum
        // can't represent it either way.
        if let raw = defaults.string(forKey: Key.qualityPreset),
           let preset = QualityPreset(rawValue: raw) {
            settings.quality = preset
        }

        // `integer(forKey:)` returns 0 for both "absent" and "garbage", and 0 fps divides by
        // zero downstream — so only the two documented values are accepted.
        let fps = defaults.integer(forKey: Key.fpsCap)
        if Settings.allowedFrameRateCaps.contains(fps) {
            settings.frameRateCap = fps
        }

        // No device-presence validation, on purpose: launching with the AirPods in their case
        // must not forget the pick (see the field's comment). Automatic wins over a stored device.
        if defaults.bool(forKey: Key.microphoneAutomatic) {
            settings.microphonePreference = .automatic
        } else if let microphoneID = defaults.string(forKey: Key.microphoneID), !microphoneID.isEmpty {
            settings.microphonePreference = .device(id: microphoneID)
        }

        // Like the mic: no running-app validation — the pick survives the app being closed.
        if let bundleID = defaults.string(forKey: Key.captureAppBundleID), !bundleID.isEmpty {
            settings.captureAppBundleID = bundleID
        }

        settings.replayArmed = defaults.bool(forKey: Key.replayArmed)

        // A positive value clamps into the range (M9-T8); absent or garbage (`integer(forKey:)` is 0
        // for both) keeps the default 60 — never a 0-length ring.
        let rawReplaySeconds = defaults.integer(forKey: Key.replaySeconds)
        if rawReplaySeconds > 0 {
            settings.replaySeconds = min(
                max(rawReplaySeconds, Settings.replaySecondsRange.lowerBound),
                Settings.replaySecondsRange.upperBound)
        }

        // A malformed hotkey falls back whole — half a shortcut is not a shortcut. `hotkey(from:)`
        // rejects zero modifiers (a bare key would fire on ordinary typing) and bounds both values
        // (they feed trapping UInt32 conversions at registration).
        if let hk = hotkey(from: defaults.dictionary(forKey: Key.replayHotkey)) {
            settings.replayHotkey = hk
        }
        // Absent or malformed ⇒ the start/stop shortcut stays off (M9-T4).
        settings.recordHotkey = hotkey(from: defaults.dictionary(forKey: Key.recordHotkey))

        // Opt-out, so absent means on (the `.standard` default holds); only an explicit stored
        // value overrides it.
        if defaults.object(forKey: Key.showsMenuBarTimer) != nil {
            settings.showsMenuBarTimer = defaults.bool(forKey: Key.showsMenuBarTimer)
        }

        return settings
    }

    /// Validates a persisted hotkey dict: both inner keys present, zero modifiers rejected, and both
    /// values bounded to fit the trapping UInt32 conversions at registration. Nil ⇒ absent/malformed.
    private static func hotkey(from dict: [String: Any]?) -> Hotkey? {
        guard let dict,
              let keyCode = dict[Key.hotkeyKeyCode] as? Int, (0...0xFFFF).contains(keyCode),
              let modifiers = dict[Key.hotkeyModifiers] as? Int, (1...0xFFFF).contains(modifiers)
        else { return nil }
        return Hotkey(keyCode: keyCode, modifiers: modifiers)
    }

    public static func save(_ settings: Settings, to defaults: UserDefaults) {
        // The path, not the URL: docs/06 says String, and a URL archives as opaque data that
        // `defaults read` can't show a human.
        defaults.set(settings.outputDirectory.path, forKey: Key.outputDirectory)
        defaults.set(settings.quality.rawValue, forKey: Key.qualityPreset)
        defaults.set(settings.frameRateCap, forKey: Key.fpsCap)
        switch settings.microphonePreference {
        case .none:
            defaults.removeObject(forKey: Key.microphoneID)
            defaults.removeObject(forKey: Key.microphoneAutomatic)
        case .automatic:
            defaults.removeObject(forKey: Key.microphoneID)
            defaults.set(true, forKey: Key.microphoneAutomatic)
        case .device(let id):
            defaults.set(id, forKey: Key.microphoneID)
            defaults.removeObject(forKey: Key.microphoneAutomatic)
        }
        // `set(_:Any?)` removes the key for nil — absent ⇒ entire screen, per the table.
        defaults.set(settings.captureAppBundleID, forKey: Key.captureAppBundleID)
        defaults.set(settings.replayArmed, forKey: Key.replayArmed)
        defaults.set(settings.replaySeconds, forKey: Key.replaySeconds)
        defaults.set(
            [Key.hotkeyKeyCode: settings.replayHotkey.keyCode,
             Key.hotkeyModifiers: settings.replayHotkey.modifiers],
            forKey: Key.replayHotkey)
        // Nil removes the key, per the table — absent ⇒ off (M9-T4).
        if let recordHotkey = settings.recordHotkey {
            defaults.set(
                [Key.hotkeyKeyCode: recordHotkey.keyCode, Key.hotkeyModifiers: recordHotkey.modifiers],
                forKey: Key.recordHotkey)
        } else {
            defaults.removeObject(forKey: Key.recordHotkey)
        }
        defaults.set(settings.showsMenuBarTimer, forKey: Key.showsMenuBarTimer)
    }
}
