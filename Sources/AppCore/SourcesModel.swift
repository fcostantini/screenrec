import CoreGraphics
import Foundation
import Observation
import RecorderCore

/// What can be captured, what is picked, and what the Source menu says about it (docs/06 items
/// 5–7). Extracted from `AppState` along the seam `PermissionsModel` (M9-T7) and `ExportModel`
/// (M14-T1) already proved.
///
/// ⚠️ An `@Observable` **class**, never a struct: a value type collapses per-property observation
/// into one, and every unrelated change would then rebuild the open menu's AppKit rows (M15-T2's
/// ruling, M6-T10's hazard).
///
/// The microphone pick deliberately stays on `AppState`: its presentation is entangled with the
/// live session's mic events, not with what is on screen (M22-T1 ruling A).
@Observable
@MainActor
public final class SourcesModel {

    // MARK: - What can be captured

    public private(set) var displays: [DisplayOption] = []
    /// Running apps for the Source picker (docs/06 item 5, M7-T2). Fetched async by the view at
    /// menu open — `SCShareableContent` takes ~a second — through `refreshCapturableApps`.
    public private(set) var capturableApps: [CapturableApp] = []
    /// On-screen windows for the Source picker (docs/06 item 5, M17-T2). Fetched async by the view
    /// at menu open, like the app list.
    public private(set) var capturableWindows: [CapturableWindow] = []

    // MARK: - What is picked

    /// The user's picks, as the plain identifiers the menu selects by: RecorderCore's
    /// `DisplaySelection` carries associated values and isn't `Hashable`, so it can't be a SwiftUI
    /// picker tag. `AppState.captureConfiguration` translates.
    public var selectedDisplayID: CGDirectDisplayID? {    // nil ⇒ whatever is the main display
        didSet {
            if selectedDisplayID != oldValue, !isRehoming { onDisplayChanged?() }
        }
    }
    /// The Source pick when it's an app (docs/06 item 5, M7-T2); nil ⇒ entire screen. Persisted,
    /// and — like the mic pick — it survives the app not running: never re-homed by absence, and
    /// a start while the app is away fails loud (never a silent whole-screen fallback).
    public var selectedAppBundleID: String? {
        didSet {
            guard selectedAppBundleID != oldValue, !isRehoming else { return }
            onPickChanged?()
        }
    }
    /// The Source pick when it's a region (docs/06 item 5, M11-T2); nil ⇒ not a region. Set via the
    /// drag overlay through `setRegion`; persisted, and — like the app pick — it survives its display
    /// vanishing (a start then fails loud, never a silent whole-screen fallback).
    public var selectedRegion: RegionSelection? {
        didSet {
            guard selectedRegion != oldValue, !isRehoming else { return }
            onPickChanged?()
        }
    }
    /// The Source pick when it's a window (docs/06 item 5, M17-T2); nil ⇒ not a window pick.
    /// Persisted, and like the app and region picks it survives its subject's absence — a start
    /// against a window that is gone (or whose id now belongs to another app) fails loud.
    public var selectedWindow: WindowSelection? {
        didSet {
            guard selectedWindow != oldValue, !isRehoming else { return }
            onPickChanged?()
        }
    }

    /// A pick changed: persist it *and* rebind an armed stream. Injected by `AppState`, which owns
    /// both.
    public var onPickChanged: (() -> Void)?
    /// The display pick changed. Not persisted — it names hardware that may be gone next launch,
    /// and `refreshDisplays` re-homes it — but an armed stream still has to rebind.
    public var onDisplayChanged: (() -> Void)?

    /// True while `refreshDisplays` re-homes a stale pick (housekeeping, not user intent) and
    /// while `sourceChoice` batches its two backing writes — either way, the suppressed didSets
    /// must not restart the armed stream: a rebuild wipes the replay buffer, and the batched
    /// case would otherwise rebuild twice, once against a config that exists for a microsecond.
    private var isRehoming = false

    public init() {}

    // MARK: - Refreshing the lists (menu open)

    /// Re-homes the display selection: docs/06 wants one row per screen with a checkmark on the
    /// current one, so the selection must name a row that exists — covering first launch and the
    /// picked display going away.
    public func refreshDisplays(_ displays: [DisplayOption]) {
        isRehoming = true
        defer { isRehoming = false }
        // Assign only on real change: @Observable publishes on every set, and a publish rebuilds
        // the open menu's AppKit rows (garbling hover/highlight, M6-T10). Menu opens re-read
        // these, usually to the same values.
        if self.displays != displays { self.displays = displays }

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = (displays.first(where: \.isMain) ?? displays.first)?.id
        }
    }

    /// Fetches and publishes the Source picker's app list; the view calls this at menu open.
    /// In-flight-guarded (a quick reopen must not stack ~1 s shareable-content fetches); a
    /// fetch failure keeps the last-known list rather than blanking an open picker.
    public func refreshCapturableApps() async {
        guard !isRefreshingApps else { return }
        isRefreshingApps = true
        defer { isRefreshingApps = false }
        guard let apps = try? await CapturableApps.available() else { return }
        refreshApps(apps)
    }
    private var isRefreshingApps = false

    /// Fetches and publishes the Source picker's window list; the view calls this at menu open,
    /// alongside the app list. Same in-flight guard and same keep-the-last-list-on-failure rule.
    public func refreshCapturableWindows() async {
        guard !isRefreshingWindows else { return }
        isRefreshingWindows = true
        defer { isRefreshingWindows = false }
        guard let windows = try? await CapturableWindows.available() else { return }
        refreshWindows(windows)
    }
    private var isRefreshingWindows = false

    /// Membership + publish, assign-on-change only (M6-T10). ScreenRec never lists itself —
    /// recording the recorder is noise; `recordableAppsFilter` applies the app layer's policy.
    /// `excluding` is injected so tests don't depend on the test runner's bundle identity.
    func refreshApps(
        _ apps: [CapturableApp], excluding ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        var apps = apps.filter { $0.bundleID != ownBundleID }
        apps = recordableAppsFilter?(apps) ?? apps
        if capturableApps != apps { capturableApps = apps }
    }

    /// Membership + publish, assign-on-change only (M6-T10). ScreenRec never lists its own windows,
    /// for the same reason it never lists itself as an app. `excluding` is injected so tests don't
    /// depend on the test runner's bundle identity.
    func refreshWindows(
        _ windows: [CapturableWindow], excluding ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        let windows = windows.filter { $0.bundleID != ownBundleID }
        if capturableWindows != windows { capturableWindows = windows }
    }

    /// Which running apps belong in the Source picker, beyond self-exclusion. Injected by the
    /// app (the activation-policy read needs NSRunningApplication — AppKit); takes the whole
    /// list so the implementation can snapshot the process table once. Nil ⇒ no extra filter.
    public var recordableAppsFilter: (([CapturableApp]) -> [CapturableApp])?

    /// Resolves an installed app's display name from its bundle ID (works while it isn't
    /// running). Injected by the app — NSWorkspace is AppKit, banned here. Nil in tests.
    public var appDisplayName: ((String) -> String?)?

    // MARK: - What the menu shows

    /// The picked app while it isn't in the live list: the menu shows it as a checkmarked
    /// "(not running)" row, so the pick stays visible without lying (the mic pattern's truth
    /// discipline, M7-T2).
    public var missingPickedApp: CapturableApp? {
        guard let bundleID = selectedAppBundleID,
              !capturableApps.contains(where: { $0.bundleID == bundleID }) else { return nil }
        return CapturableApp(bundleID: bundleID, name: appName(for: bundleID))
    }

    /// The picked window while it isn't in the live list — closed, or its id now belongs to another
    /// app. The menu shows it checkmarked and marked gone, so the pick stays visible without lying
    /// (the `(not running)` app precedent); Start then fails loud.
    public var missingPickedWindow: WindowSelection? {
        guard let selectedWindow, selectedWindow.resolve(in: capturableWindows) == nil else { return nil }
        return selectedWindow
    }

    /// Bundle ID → display name: the live list, then the installed-app resolver, then the ID
    /// itself — the one fallback chain, and it never returns an empty string.
    public func appName(for bundleID: String) -> String {
        capturableApps.first { $0.bundleID == bundleID }?.name
            ?? appDisplayName?(bundleID)
            ?? bundleID
    }

    /// The current Source pick as menu text (M12-T3), so the submenu title tells the truth without
    /// being opened: `Region 1645×721`, an app's name, or the whole screen (named when there's a
    /// choice of display). Mirrors the checkmarked picker row.
    public var sourceMenuLabel: String {
        if let window = selectedWindow {
            // Always from the live window, so a retitled one stays honest; a gone pick can only
            // name its app (M19-T5).
            guard let live = window.resolve(in: capturableWindows) else {
                return WindowSelection.goneLabel(appName: appName(for: window.bundleID))
            }
            return WindowSelection.label(appName: live.appName, title: live.title)
        }
        if let region = selectedRegion { return "Region \(Self.regionLabel(region.rect.size))" }
        if let bundleID = selectedAppBundleID { return appName(for: bundleID) }
        if displays.count > 1,
           let screen = displays.first(where: { $0.id == selectedDisplayID }) {
            return "Entire Screen (\(screen.name))"
        }
        return "Entire Screen"
    }

    /// "<w>×<h>" for a region's size in points, e.g. the picker's `Region 820×512` row. The
    /// engine snaps to even pixels at capture (M11-T1); the menu shows the chosen point size.
    public static func regionLabel(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }

    // MARK: - The picker's one selection

    /// The Source picker's one Hashable selection over its row kinds (docs/06 item 5, M7-T2/M11-T2).
    /// Writing one kind clears the others; the remembered display survives an app/region detour.
    /// The backing writes are batched (`isRehoming`) into ONE persist + rebuild.
    public var sourceChoice: SourceChoice {
        get {
            if let window = selectedWindow { return .window(window) }
            if let region = selectedRegion { return .region(display: region.displayID, rect: region.rect) }
            return selectedAppBundleID.map { .app(bundleID: $0) } ?? .display(selectedDisplayID)
        }
        set {
            guard newValue != sourceChoice else { return }
            isRehoming = true
            switch newValue {
            case .display(let id):
                selectedAppBundleID = nil
                selectedRegion = nil
                selectedWindow = nil
                selectedDisplayID = id
            case .app(let bundleID):
                selectedAppBundleID = bundleID
                selectedRegion = nil
                selectedWindow = nil
            case .region(let displayID, let rect):
                selectedAppBundleID = nil
                selectedWindow = nil
                selectedRegion = RegionSelection(displayID: displayID, rect: rect)
            case .window(let window):
                selectedAppBundleID = nil
                selectedRegion = nil
                selectedWindow = window
            }
            isRehoming = false
            onPickChanged?()
        }
    }

    /// Sets a drawn region as the Source (M11-T2) — the overlay's one entry point. Goes through
    /// `sourceChoice` so it inherits the batched persist + single armed-stream rebuild.
    public func setRegion(displayID: CGDirectDisplayID?, rect: CGRect) {
        sourceChoice = .region(display: displayID, rect: rect)
    }

    // MARK: - Geometry of the pick

    /// Pixels the armed stream encodes, mirroring `CaptureEngine`'s own resolution: a region's rect
    /// on its display; an app filter composites **on the main display** whatever display the pickers
    /// remember, and its frames stay display-sized (02 §1a); a whole-screen pick follows the
    /// selection. Nil when that display's geometry is unknown.
    var capturePixelSize: (width: Int, height: Int)? {
        guard let screen = displayForCurrentSelection,
              screen.pointPixelScale > 0, screen.pointSize != .zero else { return nil }
        return CaptureConfiguration.pixelDimensions(
            pointSize: selectedRegion?.rect.size ?? screen.pointSize,
            pointPixelScale: screen.pointPixelScale)
    }

    /// The whole display a capture would land on, ignoring any region narrowing — what a
    /// full-screen recording of the current pick measures. The export Size picker quotes this and
    /// not `capturePixelSize`: a region pick says nothing about the size of the *file* being
    /// exported, which may be an older full-screen take.
    var displayPixelSize: (width: Int, height: Int)? {
        guard let screen = displayForCurrentSelection,
              screen.pointPixelScale > 0, screen.pointSize != .zero else { return nil }
        return CaptureConfiguration.pixelDimensions(
            pointSize: screen.pointSize, pointPixelScale: screen.pointPixelScale)
    }

    private var displayForCurrentSelection: DisplayOption? {
        let displayID = selectedRegion?.displayID
            ?? (selectedAppBundleID == nil ? selectedDisplayID : nil)
        return displayOption(for: displayID)
    }

    /// A display id as its option; a nil id means the main display, matching the engine's `.main`.
    private func displayOption(for id: CGDirectDisplayID?) -> DisplayOption? {
        guard let id else { return displays.first(where: \.isMain) ?? displays.first }
        return displays.first { $0.id == id }
    }
}
