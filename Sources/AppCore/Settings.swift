import Foundation
import RecorderCore

/// The global shortcut that saves a replay. Raw Carbon values — `keyCode` is a virtual key
/// code (kVK_*) and `modifiers` a Carbon modifier mask (cmdKey/optionKey/…), because that's
/// what `RegisterEventHotKey` takes; the app layer owns the Carbon import and the display
/// formatting.
public struct ReplayHotkey: Sendable, Equatable {
    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌥⌘R (docs/06): kVK_ANSI_R with optionKey | cmdKey.
    public static let standard = ReplayHotkey(keyCode: 15, modifiers: 2048 | 256)
}

/// The app's persisted preferences (docs/06 "Settings window").
///
/// Launch-at-login (M6) arrives with the feature it configures.
public struct Settings: Sendable, Equatable {
    public var outputDirectory: URL
    public var quality: QualityPreset
    /// docs/06 offers 30 or 60.
    public var frameRateCap: Int
    public var replayArmed: Bool
    /// docs/06 offers 30, 60 or 120.
    public var replaySeconds: Int
    public var replayHotkey: ReplayHotkey

    public static let allowedFrameRateCaps = [30, 60]
    public static let allowedReplaySeconds = [30, 60, 120]

    public static var standard: Settings {
        Settings(
            outputDirectory: OutputLocation.defaultDirectory(),
            quality: .balanced,
            frameRateCap: 60,
            replayArmed: false,
            replaySeconds: 60,
            replayHotkey: .standard)
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
        public static let replayArmed = "replayArmed"
        public static let replaySeconds = "replaySeconds"
        public static let replayHotkey = "replayHotkey"
        /// `replayHotkey` is a Dict (docs/06): these are its inner keys.
        public static let hotkeyKeyCode = "keyCode"
        public static let hotkeyModifiers = "modifiers"
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

        settings.replayArmed = defaults.bool(forKey: Key.replayArmed)

        // Same shape as fps: only the documented values, or a ring gets sized by garbage.
        let replaySeconds = defaults.integer(forKey: Key.replaySeconds)
        if Settings.allowedReplaySeconds.contains(replaySeconds) {
            settings.replaySeconds = replaySeconds
        }

        // A malformed hotkey falls back whole — half a shortcut is not a shortcut. Zero
        // modifiers is rejected (a bare key would fire on ordinary typing), and both values
        // are bounded: they feed trapping UInt32 conversions at registration, so an oversized
        // plist value would otherwise crash every launch.
        if let dict = defaults.dictionary(forKey: Key.replayHotkey),
           let keyCode = dict[Key.hotkeyKeyCode] as? Int, (0...0xFFFF).contains(keyCode),
           let modifiers = dict[Key.hotkeyModifiers] as? Int, (1...0xFFFF).contains(modifiers) {
            settings.replayHotkey = ReplayHotkey(keyCode: keyCode, modifiers: modifiers)
        }

        return settings
    }

    public static func save(_ settings: Settings, to defaults: UserDefaults) {
        // The path, not the URL: docs/06 says String, and a URL archives as opaque data that
        // `defaults read` can't show a human.
        defaults.set(settings.outputDirectory.path, forKey: Key.outputDirectory)
        defaults.set(settings.quality.rawValue, forKey: Key.qualityPreset)
        defaults.set(settings.frameRateCap, forKey: Key.fpsCap)
        defaults.set(settings.replayArmed, forKey: Key.replayArmed)
        defaults.set(settings.replaySeconds, forKey: Key.replaySeconds)
        defaults.set(
            [Key.hotkeyKeyCode: settings.replayHotkey.keyCode,
             Key.hotkeyModifiers: settings.replayHotkey.modifiers],
            forKey: Key.replayHotkey)
    }
}
