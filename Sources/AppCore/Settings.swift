import Foundation
import RecorderCore

/// The app's persisted preferences (docs/06 "Settings window").
///
/// Replay (M5) and launch-at-login (M6) settings arrive with the features they configure.
public struct Settings: Sendable, Equatable {
    public var outputDirectory: URL
    public var quality: QualityPreset
    /// docs/06 offers 30 or 60.
    public var frameRateCap: Int

    public static let allowedFrameRateCaps = [30, 60]

    public static var standard: Settings {
        Settings(
            outputDirectory: OutputLocation.defaultDirectory(),
            quality: .balanced,
            frameRateCap: 60)
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

        return settings
    }

    public static func save(_ settings: Settings, to defaults: UserDefaults) {
        // The path, not the URL: docs/06 says String, and a URL archives as opaque data that
        // `defaults read` can't show a human.
        defaults.set(settings.outputDirectory.path, forKey: Key.outputDirectory)
        defaults.set(settings.quality.rawValue, forKey: Key.qualityPreset)
        defaults.set(settings.frameRateCap, forKey: Key.fpsCap)
    }
}
