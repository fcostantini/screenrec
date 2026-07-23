import CoreGraphics
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

    /// ⌥⌘P: the combo seeded when the user first enables the pause/resume shortcut (M12-T6).
    /// kVK_ANSI_P with optionKey | cmdKey.
    public static let pauseDefault = Hotkey(keyCode: 35, modifiers: 2048 | 256)
}

/// The user's microphone pick, before resolution to a concrete device (docs/06 item 6):
/// a specific device, `automatic` (follow the system default at capture start, M6-T13), or none.
public enum MicrophonePreference: Sendable, Equatable, Hashable {
    case none
    case automatic
    case device(id: String)
}

/// A persisted region pick (docs/06 item 5, M11-T2): a display and a rectangle in that display's
/// SCK `sourceRect` space (top-left origin, points — docs/02 §1b). Persisted like the app pick;
/// an off-screen rect after a resolution change still fails loud at start (M11-T1's `resolveRegion`).
public struct RegionSelection: Hashable, Sendable {
    public var displayID: CGDirectDisplayID?  // nil ⇒ the main display
    public var rect: CGRect

    public init(displayID: CGDirectDisplayID?, rect: CGRect) {
        self.displayID = displayID
        self.rect = rect
    }

    /// Converts a selection rectangle from AppKit view/screen points (bottom-left origin, the
    /// overlay's space) to SCK `sourceRect` points (top-left origin — docs/02 §1b), given the
    /// display's height in points. The one geometry flip between the overlay and the engine.
    public static func sckRect(fromViewRect view: CGRect, displayHeightPoints: CGFloat) -> CGRect {
        CGRect(x: view.origin.x, y: displayHeightPoints - (view.origin.y + view.height),
               width: view.width, height: view.height)
    }

    /// The overlay size badge (M12-T4): points and pixels, e.g. `960 × 540 pt · 1920 × 1080 px` — a
    /// power user framing exactly 1920×1080 px needs the pixel size (points × the display's backing
    /// scale). Pure, so the formatting is unit-tested away from the AppKit drawing.
    public static func badgeText(width: CGFloat, height: CGFloat, scale: CGFloat) -> String {
        let wpt = Int(width.rounded()), hpt = Int(height.rounded())
        let wpx = Int((width * scale).rounded()), hpx = Int((height * scale).rounded())
        return "\(wpt) × \(hpt) pt · \(wpx) × \(hpx) px"
    }

    /// The overlay's honesty caveat (M12-T4): region capture is main-display only (M11), so on a
    /// multi-display Mac the overlay says so; a single display needs no caveat (nil). Pure predicate.
    public static func mainDisplayHint(displayCount: Int) -> String? {
        displayCount > 1 ? "Region capture uses the main display only" : nil
    }
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
    /// The Source pick when it's a region (docs/06 item 5, M11-T2). Nil ⇒ not a region pick. Like
    /// the app pick, not validated against the current displays at load — a start against a vanished
    /// display fails loud (M11-T1).
    public var captureRegion: RegionSelection?
    public var replayArmed: Bool
    /// docs/06 offers 30, 60 or 120.
    public var replaySeconds: Int
    public var replayHotkey: Hotkey
    /// The optional global start/stop recording shortcut (M9-T4). Nil ⇒ off — an always-live combo
    /// the user didn't choose could silently clash, so this is opt-in.
    public var recordHotkey: Hotkey?
    /// The optional global pause/resume shortcut (M12-T6). Nil ⇒ off — opt-in like `recordHotkey`.
    public var pauseHotkey: Hotkey?
    /// Whether Start runs a 3-2-1 count-in first (M12-T6). Default off.
    public var countInEnabled: Bool
    /// Whether the menu-bar label shows the live elapsed clock while recording (M9-T3). Default on.
    public var showsMenuBarTimer: Bool
    /// The GIF export caps (M10-T3 follow-up): each is one of its `allowedGif…` list. Width also
    /// caps height (aspect preserved). Steer `Save as GIF`; the CLI takes its own flags.
    public var gifFPS: Int
    public var gifWidth: Int
    public var gifMaxSeconds: Int
    /// Whether the one-time "banners are hidden while armed" alert has been shown (M12-T5). Absent
    /// ⇒ false (not yet seen); once true the alert never fires again — the dimmed menu row is the
    /// ongoing reminder.
    public var seenReplayBannerWarning: Bool

    public static let allowedFrameRateCaps = [30, 60]
    public static let allowedGifFPS = [12, 15, 20, 24]
    public static let allowedGifWidths = [320, 480, 640, 800]
    public static let allowedGifMaxSeconds = [10, 15, 30, 60]

    /// The list member closest to `value` (ties → the lower), so a hand-edited or future-version
    /// plist value snaps to a real picker choice instead of leaving the Picker blank.
    static func nearest(_ value: Int, in allowed: [Int]) -> Int? {
        allowed.min { abs($0 - value) < abs($1 - value) }
    }
    /// The replay buffer length range (M9-T8): 5 s floor → 15 min. Seconds granularity via typed
    /// input; the slider snaps to `replaySliderStep`.
    public static let replaySecondsRange = 5...900
    /// The slider lands on 15-second increments (M9-T8); finer values come from the typed field.
    public static let replaySliderStep = 15

    /// The replay length as `M:SS` (M9-T8): 200 → "3:20", 5 → "0:05".
    public static func replayBufferLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Parses the typed replay length — `"M:SS"` or a plain seconds count — clamped into range;
    /// nil if it isn't a number (the field then reverts). `"3:20"` → 200, `"200"` → 200, `"0:03"` → 5.
    public static func parseReplayBuffer(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let seconds: Int
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let minutes = Int(parts[0]),
                  let secs = Int(parts[1]), (0..<60).contains(secs) else { return nil }
            seconds = minutes * 60 + secs
        } else {
            guard let secs = Int(trimmed) else { return nil }
            seconds = secs
        }
        return min(max(seconds, replaySecondsRange.lowerBound), replaySecondsRange.upperBound)
    }

    public static var standard: Settings {
        Settings(
            outputDirectory: OutputLocation.defaultDirectory(),
            quality: .balanced,
            frameRateCap: 60,
            microphonePreference: .none,
            captureAppBundleID: nil,
            captureRegion: nil,
            replayArmed: false,
            replaySeconds: 60,
            replayHotkey: .standard,
            recordHotkey: nil,
            pauseHotkey: nil,
            countInEnabled: false,
            showsMenuBarTimer: true,
            gifFPS: 15,
            gifWidth: 480,
            gifMaxSeconds: 30,
            seenReplayBannerWarning: false)
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
        /// Absent ⇒ not a region pick (M11-T2). A Dict of the inner keys below.
        public static let captureRegion = "captureRegion"
        /// Inner keys of `captureRegion` — the display id and the rect (SCK points, docs/02 §1b).
        public static let regionDisplay = "display"
        public static let regionX = "x"
        public static let regionY = "y"
        public static let regionWidth = "width"
        public static let regionHeight = "height"
        public static let replayArmed = "replayArmed"
        public static let replaySeconds = "replaySeconds"
        public static let replayHotkey = "replayHotkey"
        /// Absent ⇒ the start/stop shortcut is off (M9-T4). Same Dict shape as `replayHotkey`.
        public static let recordHotkey = "recordHotkey"
        /// Absent ⇒ the pause/resume shortcut is off (M12-T6). Same Dict shape as `replayHotkey`.
        public static let pauseHotkey = "pauseHotkey"
        /// Absent ⇒ no count-in (M12-T6).
        public static let countInEnabled = "countInEnabled"
        /// `replayHotkey`/`recordHotkey` are Dicts (docs/06): these are their inner keys.
        public static let hotkeyKeyCode = "keyCode"
        public static let hotkeyModifiers = "modifiers"
        /// Absent ⇒ on (M9-T3): the menu-bar clock is opt-out, not opt-in.
        public static let showsMenuBarTimer = "showsMenuBarTimer"
        /// Absent ⇒ the first-arm banner-suppression alert hasn't been shown (M12-T5).
        public static let seenReplayBannerWarning = "seenReplayBannerWarning"
        /// The GIF export caps (M10-T3 follow-up); absent ⇒ 15 / 480 / 30.
        public static let gifFPS = "gifFPS"
        public static let gifWidth = "gifWidth"
        public static let gifMaxSeconds = "gifMaxSeconds"
        /// The last export's path, for the receipt that survives relaunch (M12-T2). Absent ⇒ no
        /// receipt. Not part of `Settings` (it's a transient pointer, not user config) — its own
        /// load/save below. Dropped on load if the file is gone (moved/trashed).
        public static let lastExportPath = "lastExportPath"
        /// When that export finished (M12-T3), so a stale receipt can expire. Stored beside the path.
        public static let lastExportDate = "lastExportDate"
    }

    /// The persisted export receipt (M12-T2/T3), validated against the filesystem: a pointer to a
    /// file that's since been moved or trashed — or a pre-T3 entry with no date — is dropped, so a
    /// broken receipt never shows. Staleness (the date) is judged later, at menu open.
    public static func loadLastExport(from defaults: UserDefaults) -> LastExport? {
        guard let path = defaults.string(forKey: Key.lastExportPath), !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let date = defaults.object(forKey: Key.lastExportDate) as? Date
        else { return nil }
        return LastExport(url: URL(fileURLWithPath: path), date: date)
    }

    public static func saveLastExport(_ export: LastExport?, to defaults: UserDefaults) {
        if let export {
            defaults.set(export.url.path, forKey: Key.lastExportPath)
            defaults.set(export.date, forKey: Key.lastExportDate)
        } else {
            defaults.removeObject(forKey: Key.lastExportPath)
            defaults.removeObject(forKey: Key.lastExportDate)
        }
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

        // Like the app pick: no display validation at load — a vanished display fails loud at start.
        if let region = regionSelection(from: defaults.dictionary(forKey: Key.captureRegion)) {
            settings.captureRegion = region
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
        settings.pauseHotkey = hotkey(from: defaults.dictionary(forKey: Key.pauseHotkey))
        settings.countInEnabled = defaults.bool(forKey: Key.countInEnabled)

        // Opt-out, so absent means on (the `.standard` default holds); only an explicit stored
        // value overrides it.
        if defaults.object(forKey: Key.showsMenuBarTimer) != nil {
            settings.showsMenuBarTimer = defaults.bool(forKey: Key.showsMenuBarTimer)
        }
        settings.seenReplayBannerWarning = defaults.bool(forKey: Key.seenReplayBannerWarning)

        // Each GIF cap snaps to its nearest picker choice; absent/garbage (0) keeps the default.
        let rawGifFPS = defaults.integer(forKey: Key.gifFPS)
        if rawGifFPS > 0, let gifFPS = Settings.nearest(rawGifFPS, in: Settings.allowedGifFPS) {
            settings.gifFPS = gifFPS
        }
        let rawGifWidth = defaults.integer(forKey: Key.gifWidth)
        if rawGifWidth > 0, let width = Settings.nearest(rawGifWidth, in: Settings.allowedGifWidths) {
            settings.gifWidth = width
        }
        let rawGifMaxSeconds = defaults.integer(forKey: Key.gifMaxSeconds)
        if rawGifMaxSeconds > 0,
           let seconds = Settings.nearest(rawGifMaxSeconds, in: Settings.allowedGifMaxSeconds) {
            settings.gifMaxSeconds = seconds
        }

        return settings
    }

    /// Validates a persisted region dict: a positive, finite rect; a non-negative display id if
    /// present (else nil ⇒ main). Nil ⇒ absent/malformed — a bad value falls back to no region.
    private static func regionSelection(from dict: [String: Any]?) -> RegionSelection? {
        guard let dict,
              let x = dict[Key.regionX] as? Double, x.isFinite,
              let y = dict[Key.regionY] as? Double, y.isFinite,
              let width = dict[Key.regionWidth] as? Double, width.isFinite, width > 0,
              let height = dict[Key.regionHeight] as? Double, height.isFinite, height > 0
        else { return nil }
        // A CGDirectDisplayID is a UInt32; an out-of-range (negative or > UInt32.max) hand-edited
        // value must fall back, not trap the cast — the loader tolerates any plist value.
        var displayID: CGDirectDisplayID?
        if let raw = dict[Key.regionDisplay] as? Int {
            guard let id = CGDirectDisplayID(exactly: raw) else { return nil }
            displayID = id
        }
        return RegionSelection(
            displayID: displayID, rect: CGRect(x: x, y: y, width: width, height: height))
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
        if let region = settings.captureRegion {
            var dict: [String: Any] = [
                Key.regionX: Double(region.rect.origin.x), Key.regionY: Double(region.rect.origin.y),
                Key.regionWidth: Double(region.rect.width), Key.regionHeight: Double(region.rect.height)]
            if let displayID = region.displayID { dict[Key.regionDisplay] = Int(displayID) }
            defaults.set(dict, forKey: Key.captureRegion)
        } else {
            defaults.removeObject(forKey: Key.captureRegion)
        }
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
        if let pauseHotkey = settings.pauseHotkey {
            defaults.set(
                [Key.hotkeyKeyCode: pauseHotkey.keyCode, Key.hotkeyModifiers: pauseHotkey.modifiers],
                forKey: Key.pauseHotkey)
        } else {
            defaults.removeObject(forKey: Key.pauseHotkey)
        }
        defaults.set(settings.countInEnabled, forKey: Key.countInEnabled)
        defaults.set(settings.showsMenuBarTimer, forKey: Key.showsMenuBarTimer)
        defaults.set(settings.seenReplayBannerWarning, forKey: Key.seenReplayBannerWarning)
        defaults.set(settings.gifFPS, forKey: Key.gifFPS)
        defaults.set(settings.gifWidth, forKey: Key.gifWidth)
        defaults.set(settings.gifMaxSeconds, forKey: Key.gifMaxSeconds)
    }
}
