import AppCore
import AppKit
import RecorderCore
import SwiftUI

/// The status item's menu (docs/06 "Menu — idle state" / "Menu — recording state").
///
/// Built fresh on each open, which is when its state is refreshed: everything pulls (`.task`)
/// rather than subscribing to timers that would tick behind a closed menu.
struct MenuView: View {
    @Bindable var state: AppState
    let windows: WindowPresenter

    /// The source pickers bind into `SourcesModel`, and `state.sources` is a `let` — so the binding
    /// is taken on the sub-model itself rather than through a path SwiftUI can't write.
    private var sources: Bindable<SourcesModel> { Bindable(state.sources) }

    var body: some View {
        if state.session.isActive {
            recordingItems
        } else {
            idleItems
        }
        Divider()
        // docs/06 item 12: present in both menus. Settings are read at the next Start, so
        // changing them mid-recording is harmless.
        //
        // A synthetic click (`tools/menudriver.swift`) can't confer activation, so window
        // ordering can only be verified by hand.
        //
        // ⌘, is bound on this row because an LSUIElement app has no app menu to route it through.
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Button("Quit") { quit() }
            .keyboardShortcut("q")
    }

    // MARK: - Idle (docs/06 items 1–10)

    @ViewBuilder private var idleItems: some View {
        // Header. docs/06 asks for a right-aligned status against a "ScreenRec" title, but a
        // `.menu`-style MenuBarExtra renders rows through AppKit and keeps only the text.
        //
        // The refresh hangs off the header rather than a `Group` around the whole menu: a Group
        // hands its modifiers to each child, so a `.task` there runs once per row.
        idleHeader
            .modifier(RefreshOnMenuOpen(refresh: refreshAtOpen))

        Divider()

        // docs/06 (M12-T3): Start is the first actionable row — the export/replay receipts sit
        // below it, never squatting above the primary action.
        startRecordingRow
        // A Start that fails before a session exists lands back here, so the reason has to render
        // in the idle menu too — otherwise Start looks like a no-op and the fail-loud promise is
        // inaudible. Sits under Start because that is the action it explains.
        if let failure = state.lastFailure {
            Text(failure)
        }
        replayControls

        Divider()

        lastRecordingRow
        exportStatusRow
        lastReplayRow

        // Source (docs/06 item 5, M7-T2): all three capture modes are entered from this one submenu
        // (M12-T4). An inline `Picker` keeps SwiftUI's reliable checkmark on the current entry (an
        // explicit hand-built Menu can't two-tone or check rows through the `.menu` bridge), and the
        // `Select Region…` action sits below it — so region entry lives with the other sources, not
        // as a stray top-level row. Screens above the divider, running apps below; a picked app that
        // isn't running stays listed and checkmarked (its Start fails loud instead). The title
        // carries the current pick (M12-T3), so a glance tells the truth without opening it.
        Menu("Source: \(state.sources.sourceMenuLabel)") {
            Picker(selection: sources.sourceChoice) {
                ForEach(state.sources.displays) { screen in
                    Text(state.sources.displays.count == 1 ? "Entire Screen" : "Entire Screen (\(screen.name))")
                        .tag(SourceChoice.display(screen.id))
                }
                Divider()
                ForEach(state.sources.capturableApps, id: \.bundleID) { app in
                    Text(app.name).tag(SourceChoice.app(bundleID: app.bundleID))
                }
                if let missing = state.sources.missingPickedApp {
                    Text("\(missing.name) (not running)")
                        .tag(SourceChoice.app(bundleID: missing.bundleID))
                        .disabled(true)
                }
                // The current region as a checkmarked, re-selectable tag (M11-T2); redraw via
                // Select Region… below. Its tag matches `sourceChoice`'s region case.
                if let region = state.sources.selectedRegion {
                    Divider()
                    Text("Region \(SourcesModel.regionLabel(region.rect.size))")
                        .tag(SourceChoice.region(display: region.displayID, rect: region.rect))
                }
            } label: { EmptyView() }
                .pickerStyle(.inline)

            // Windows nest one level down (M17-T2): there are routinely a dozen or more, and
            // Source is already the longest submenu — M18-T3 is shortening it, not lengthening it.
            // Its own inline Picker over the same `sourceChoice` binding keeps the checkmark
            // wherever the pick actually is.
            Menu("Window") {
                Picker(selection: sources.sourceChoice) {
                    ForEach(state.sources.capturableWindows, id: \.id) { window in
                        Text(WindowSelection.label(appName: window.appName, title: window.title))
                            .tag(SourceChoice.window(WindowSelection(
                                id: window.id, bundleID: window.bundleID)))
                    }
                    // A picked window that is gone stays listed and checkmarked — the pick survives
                    // absence (the `(not running)` app rule); Start then fails loud.
                    if let missing = state.sources.missingPickedWindow {
                        Text(WindowSelection.goneLabel(appName: state.sources.appName(for: missing.bundleID)))
                            .tag(SourceChoice.window(missing))
                    }
                } label: { EmptyView() }
                    .pickerStyle(.inline)
            }
            // The whole screen minus one app (M21-T4), nested like Window ▸ for the same reason.
            // "Nothing" is how the exclusion is undone without leaving the submenu.
            Menu("Everything Except") {
                Picker(selection: sources.sourceChoice) {
                    Text("Nothing").tag(SourceChoice.display(state.sources.selectedDisplayID))
                    Divider()
                    ForEach(state.sources.capturableApps, id: \.bundleID) { app in
                        Text(app.name).tag(SourceChoice.displayExcluding(bundleID: app.bundleID))
                    }
                    // A picked app with nothing on screen can't be excluded at capture — the pick
                    // stays (absence never re-homes one), and the start says what didn't happen.
                    if let missing = state.sources.missingExcludedApp {
                        Text("\(missing.name) (not on screen)")
                            .tag(SourceChoice.displayExcluding(bundleID: missing.bundleID))
                    }
                } label: { EmptyView() }
                    .pickerStyle(.inline)
            }
            // Heard no more, while its windows stay in frame (M27-T3). A separate row from
            // Everything Except because it is a separate idea — and a separate list: only apps the
            // audio system knows can be silenced at all (docs/07).
            Menu("Mute") {
                let silenceable = state.sources.silenceableApps()
                if silenceable.isEmpty {
                    Text("Nothing is playing").disabled(true)
                } else {
                    Button("Nothing") { state.sources.mutedAppBundleID = nil }
                    Divider()
                    ForEach(silenceable, id: \.bundleID) { app in
                        Button(state.sources.mutedAppBundleID == app.bundleID ? "✓ \(app.name)" : app.name) {
                            state.sources.mutedAppBundleID = app.bundleID
                        }
                    }
                }
            }
            // No explicit Divider here: the inline Picker already renders a trailing separator, so
            // Select Region… is cleanly set apart from the options (a second divider would double up).

            // Opens the drag-to-select overlay (M11-T2) — an action, not a picker tag.
            Button("Select Region…") { state.beginRegionSelection?() }
        }

        // docs/06 item 5 (M21-T4): the exclusion takes the picture as well as the sound, and nobody
        // should discover that by watching the file. One row, only when something is excluded.
        if let excluded = state.excludedAppName {
            Text("\(excluded) won't be seen or heard")
        }
        // The other half of that sentence (M27-T3). `mutedAppName` is nil when the exclusion above
        // already covers the app, so the stronger line stands alone rather than two arguing.
        if let muted = state.mutedAppName {
            Text("\(muted) will be seen but not heard")
            // Muting switches system audio to a process tap, which carries apps SCK's own capture
            // omits — so a muted take can hold *more* sound, not less (M27-T2, measured).
            Text("Sound from apps with no window is captured too")
        }

        // Reads through `presentMicrophonePreference`: the checkmark sits on None while a picked
        // device is away, without forgetting the pick. Writes are real user picks. Automatic
        // (docs/06 item 6) follows the system default at capture start.
        Picker("Microphone: \(state.microphoneMenuLabel)", selection: Binding(
            get: { state.presentMicrophonePreference },
            set: { state.microphonePreference = $0 }
        )) {
            Text("None").tag(MicrophonePreference.none)
            Text("Automatic (System Default)").tag(MicrophonePreference.automatic)
            Divider()
            ForEach(state.microphones, id: \.uniqueID) { device in
                Text(device.name).tag(MicrophonePreference.device(id: device.uniqueID))
            }
        }

        // ADR-019: the other half of the audio picture, beside the mic it pairs with.
        Toggle("Capture System Audio", isOn: $state.capturesSystemAudio)
        if let warning = state.silentRecordingWarning {
            Text(warning)
        }

        Picker("Quality: \(state.quality.menuTitle)", selection: $state.quality) {
            ForEach(QualityPreset.allCases, id: \.self) { preset in
                Text(preset.menuTitle).tag(preset)
            }
        }

        // A bound for the next take (M18-T4): unattended captures, and a ceiling on the all-day
        // recording nobody stopped.
        Picker("Stop After: \(MenuHeader.stopAfter(state.stopAfterMinutes))",
               selection: $state.stopAfterMinutes) {
            ForEach(Settings.allowedStopAfterMinutes, id: \.self) { minutes in
                Text(MenuHeader.stopAfter(minutes)).tag(minutes)
            }
        }

        // Only when it is news: on a healthy disk this says nothing at all (M18-T4).
        if let room = RecordingRoom.phrase(
            seconds: state.recordingRoomSeconds, presetName: state.quality.menuTitle) {
            Text(room)
        }

        Divider()

        // The whole file browser, one level down (M18-T3, docs/06 item 9).
        Menu("Recordings") {
            Button("Open Folder — \(MenuHeader.recordingsFolder(state.outputDirectory))") {
                Finder.open(state.outputDirectory)
            }

            if !state.recentRecordings.isEmpty {
                Divider()
                fileRows(state.recentRecordings)
            }

            // Recent Exports (M12-T2): derived .mp4/.gif get their own group so they don't crowd
            // the recordings out of the 5-row window; same submenu, so they inherit share/copy.
            if !state.recentExports.isEmpty {
                Divider()
                Text("Recent Exports")
                fileRows(state.recentExports)
            }
        }
    }

    // MARK: - Recording / paused (docs/06 items 1–7)

    @ViewBuilder private var recordingItems: some View {
        // Header values stamp per open and hold: a publish rebuilds the open menu's AppKit
        // rows and garbles hover (M6-T10), so nothing may tick while it's up.
        Text("\(Timecode.clock(state.session.elapsedSeconds)) — "
             + MenuHeader.recordingDetail(bytes: state.session.recordedBytes))
            .modifier(RefreshOnMenuOpen(refresh: refreshAtOpen))

        Divider()

        lastRecordingRow
        exportStatusRow
        lastReplayRow

        // Pause/Resume advertise the opt-in pause shortcut (M12-T6), Stop the start/stop one (M12-T3).
        if state.session.isPaused {
            shortcutRow("Resume", hotkey: state.pauseHotkey) { Task { await state.resume() } }
        } else {
            shortcutRow("Pause", hotkey: state.pauseHotkey) { Task { await state.pause() } }
        }
        // The combo sits on whichever ending it actually has (M24-T2) — one keypress with two
        // meanings is only honest if the menu says which one is live.
        shortcutRow("Stop & Save", hotkey: state.stopAndSaveHotkey) { Task { await state.stop() } }
        // docs/06 recording item 3b (M21-T2): stop, transcode, and leave it on the clipboard.
        // Disabled while an export runs — `performExport` would drop the second one, and a dropped
        // action must be visible rather than silent (M17-T2). The row above it says what's running.
        shortcutRow(state.stopAndCopyTitle, hotkey: state.stopAndCopyHotkey) {
            Task { await state.stopAndShare() }
        }
        .disabled(state.exports.exportInProgress != nil)

        Divider()

        if let failure = state.lastFailure {
            Text(failure)
        } else {
            // docs/06 recording item 5 (M7-T2/M11-T2): a scoped recording names its subject.
            if let app = state.session.activeAppName {
                Text("Recording \(app) only")
            }
            if let region = state.session.activeRegion {
                Text("Recording region \(SourcesModel.regionLabel(region))")
            }
            if let microphone = state.session.activeMicrophoneName {
                Text("\(microphone) · separate track")
            }
        }

        replayControls

        // The bound this take is running under (M18-T4), as an absolute time: a countdown would
        // have to tick, and the menu is stamped at open (M6-T10).
        if let stopsAt = state.stopsAt {
            Text(MenuHeader.stopsAt(stopsAt))
        }

        // docs/06: the pickers are hidden while recording, not disabled — this row says why.
        Text("Sources locked while recording")

        Divider()

        // docs/06 recording item 9: subordinate to Stop & Save and set apart from it — the one
        // irreversible action must not sit under Stop's muscle memory. Confirmed before it acts.
        // Red via NSColor: `.foregroundStyle`/`role: .destructive` don't survive the `.menu`
        // MenuBarExtra bridge (it keeps only the text) — an attributed title does (docs/06).
        Button(role: .destructive) { discardRecording() } label: {
            Text(Self.discardTitle)
        }
    }

    /// A banner-independent "Replay saved" confirmation (M9-T2, docs/06 §Notifications): while
    /// armed the screen is captured, so macOS suppresses the notification — this row is the
    /// receipt, revealing the clip on click. Renders nothing (and no divider) until a save this
    /// armed session; cleared on disarm.
    @ViewBuilder private var lastReplayRow: some View {
        if let last = state.lastReplay {
            Menu(last.menuTitle) { fileActions(last.url) }
            Divider()
        }
    }

    /// The take that just stopped (M24-T3), the receipt `lastReplay` has always had. Titled by
    /// length, not filename: the timestamped name is what makes `Recordings ▸` hard to scan.
    /// Above the export receipt because a take precedes anything derived from it — with
    /// Stop & Copy MP4 both rows are present and point at their own file.
    @ViewBuilder private var lastRecordingRow: some View {
        if let last = state.lastRecording {
            Menu(last.menuTitle) { fileActions(last.url) }
            Divider()
        }
    }

    /// The MP4 export's in-menu signal (M10-T2), shared by both menus: an "Exporting…" row while
    /// one runs (stamped at open — nothing may tick into an open menu, M6-T10), then a receipt
    /// submenu over the export (M12-T1: share/copy/Quick Look it too). The `.mov`-only recents list
    /// never shows the export, so this is its pointer.
    @ViewBuilder private var exportStatusRow: some View {
        if let name = state.exports.exportInProgress {
            Text("Exporting \(name)…")
            Divider()
        } else if let last = state.exports.lastExport {
            Menu(last.menuTitle) { fileActions(last.url) }
            Divider()
        }
    }

    /// One row per file: each is a submenu (M10-T2) titled with what distinguishes takes —
    /// `<name> — 23:04 · 5.5 GB` once the details arrive (M18-T3).
    @ViewBuilder private func fileRows(_ urls: [URL]) -> some View {
        ForEach(urls, id: \.self) { url in
            Menu(state.rowTitle(for: url)) { fileActions(url) }
        }
    }

    /// A row action that first checks the file is still there; if it isn't, the state layer says
    /// so and refreshes the rows (M18-T4). Every file action is built through this, so one that
    /// forgets to check can't be written — the rows are stamped at open, so the race is normal.
    @ViewBuilder private func fileButton(
        _ title: String, _ url: URL, _ action: @escaping (URL) -> Void
    ) -> some View {
        Button(title) {
            guard state.fileStillExists(url) else { return }
            action(url)
        }
    }

    /// The per-file submenu shared by recents, the replay receipt and the export receipt. Two groups:
    /// act on this file (reveal · Quick Look · Share · Copy, M12-T1), then derive a new one — a
    /// shareable MP4 / looping GIF (blocked while one export runs) or the Trim window.
    @ViewBuilder private func fileActions(_ url: URL) -> some View {
        fileButton("Reveal in Finder", url, Finder.reveal)
        fileButton("Quick Look", url, ShareActions.quickLook)
        fileButton("Share…", url, ShareActions.share)
        fileButton("Copy", url, ShareActions.copy)

        // Only the derives this file can actually take (M24-T5): a GIF is unreadable to
        // AVFoundation, and an export doesn't need re-exporting. The rule lives in `DeriveOptions`.
        let derives = DeriveOptions(for: url)
        if derives.hasAny {
            Divider()

            if derives.canExportToMP4 {
                fileButton("Export as MP4", url) { state.exportToMP4($0) }
                    .disabled(state.exports.exportInProgress != nil)
            }
            if derives.canSaveAsGIF {
                fileButton("Save as GIF", url) { state.exportToGIF($0) }
                    .disabled(state.exports.exportInProgress != nil)
            }
            if derives.canTrim {
                fileButton("Trim…", url) { url in
                    state.exports.trimTarget = url
                    windows.show(.trim)
                }
            }
        }

        Divider()

        // Manage the file (M12-T2). Trash is reversible, so no confirmation; red via an attributed
        // title (the `.menu` bridge drops `role:.destructive` color — the Discard precedent).
        fileButton("Rename…", url) { url in
            ShareActions.rename(url) { state.rename(url, to: $0) }
        }
        // Not `fileButton`: the title is attributed (red), which a plain Button label can't carry.
        Button {
            guard state.fileStillExists(url) else { return }
            state.moveToTrash(url)
        } label: { Text(Self.moveToTrashTitle) }
    }

    private static let moveToTrashTitle = AttributedString(NSAttributedString(
        string: "Move to Trash", attributes: [.foregroundColor: NSColor.systemRed]))

    /// Arm toggle + save row, shared by both menus (docs/06 idle item 3 / recording item 5:
    /// arming mid-recording attaches to the live stream, disarming detaches; the recording is
    /// unaffected). The readiness gate also guards a permission revoked mid-recording.
    @ViewBuilder private var replayControls: some View {
        Toggle("Arm Instant Replay", isOn: $state.isReplayArmed)
            .disabled(state.readiness != .ready && !state.isReplayArmed)
        if state.isReplayArmed {
            // What arming costs (M16-T2): the ring's memory, and ADR-018's deliberate wakefulness.
            Text(state.replayBufferMenuLabel)
            // docs/06 §Notifications (M12-T5): while armed the screen is captured, so macOS hides
            // every app's banners — unless the user allowed them when sharing (not readable via API,
            // so "may"). A standing, dimmed reminder of why they might have gone quiet.
            Text("Notification banners may be hidden while armed")
            saveReplayRow
        }
    }

    /// The shortcut column shows the user's combo (docs/06's "⌥⌘R saves" hint, live); a combo
    /// SwiftUI can't map falls back into the title so the hint never disappears entirely.
    @ViewBuilder private var saveReplayRow: some View {
        if let key = HotkeyDisplay.keyEquivalent(for: state.replayHotkey) {
            Button("Save Replay Now") { state.saveReplay() }
                .keyboardShortcut(key, modifiers: HotkeyDisplay.eventModifiers(for: state.replayHotkey))
        } else {
            Button("Save Replay Now · \(HotkeyDisplay.string(for: state.replayHotkey))") {
                state.saveReplay()
            }
        }
    }

    /// Start Recording, first actionable row, advertising the opt-in start/stop shortcut (M12-T3).
    @ViewBuilder private var startRecordingRow: some View {
        shortcutRow("Start Recording", hotkey: state.recordHotkey) { Task { await state.start() } }
            .disabled(state.readiness != .ready)
    }

    /// An action row advertising its opt-in global shortcut when set (M12-T3/T6) — the `saveReplayRow`
    /// pattern: the glyph column when SwiftUI can map the combo, else a `· ⌥⌘S` title suffix; a plain
    /// title when off. Start/Stop pass `recordHotkey`; Pause/Resume pass `pauseHotkey`.
    @ViewBuilder private func shortcutRow(
        _ title: String, hotkey: Hotkey?, action: @escaping () -> Void
    ) -> some View {
        if let hotkey, let key = HotkeyDisplay.keyEquivalent(for: hotkey) {
            Button(title, action: action)
                .keyboardShortcut(key, modifiers: HotkeyDisplay.eventModifiers(for: hotkey))
        } else if let hotkey {
            Button("\(title) · \(HotkeyDisplay.string(for: hotkey))", action: action)
        } else {
            Button(title, action: action)
        }
    }

    /// Always a button, never inert text: docs/06 draws it disabled outside blocking conditions,
    /// but notifications don't block, so `needsOnboarding` goes false and a user who dismissed
    /// the prompt would have no route back to the setup window. Auto-open still only fires on a
    /// blocking condition (docs/06 item 1).
    private var idleHeader: some View {
        Button("ScreenRec — \(MenuHeader.idleStatus(state.readiness))") { showOnboarding() }
    }

    private func showOnboarding() { windows.show(.onboarding) }

    private func showSettings() { windows.show(.settings) }

    // MARK: - Lifecycle

    /// Re-reads sources/recents/progress once per menu open. Each callee assigns only on a real
    /// change, so a no-op reopen publishes nothing and the open menu isn't rebuilt (M6-T10).
    private func refreshAtOpen() {
        state.refreshRecentRecordings()
        state.refreshRecordingRoom()
        Task { await state.refreshRecentDetails() }
        state.exports.expireStaleReceipt()   // drop a receipt aged out since a prior session (M12-T3)
        state.expireStaleRecordingReceipt()  // …and the take receipt, on the same clock (M24-T3)
        if !state.session.isActive {
            state.refreshSources(displays: DisplayOption.liveScreens())
            // Async because SCShareableContent takes ~a second; on the first open the app rows
            // land a beat late, like the recents. Publishes only on a real change.
            Task { await state.refreshCapturableApps() }
            Task { await state.refreshCapturableWindows() }
        }
        state.session.refreshProgress()
    }

    /// Runs a modal confirmation, reporting whether the **first** button was chosen. Every caller
    /// puts the safe choice first, so it is the one Return picks.
    ///
    /// The app is `LSUIElement`, so it must activate itself or the alert renders inactive and its
    /// buttons can't be reached (docs/07).
    private static func confirm(
        _ message: String, _ informative: String,
        first: String, second: String, secondIsDestructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: first)
        alert.addButton(withTitle: second).hasDestructiveAction = secondIsDestructive
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// docs/06 item 12: quitting mid-recording confirms, then finalizes before exit (ADR-007).
    /// An export in flight confirms too (M23-T2) — quitting through it loses work silently.
    private func quit() {
        if state.session.isActive {
            guard Self.confirm(
                "Stop recording and quit?", "Your recording will be saved first.",
                first: "Stop & Quit", second: "Keep Recording")
            else { return }
            Task {
                await state.finishWorkInFlight()
                NSApplication.shared.terminate(nil)
            }
            return
        }

        guard state.exports.exportInProgress != nil else { return NSApplication.shared.terminate(nil) }

        guard Self.confirm(
            "An export is still running.",
            "Quitting now throws it away. The recording it came from is untouched.",
            first: "Wait for Export", second: "Quit Anyway")
        else {
            // Abandon it first: `terminate` runs `applicationShouldTerminate`, which waits for an
            // export in flight — so without this, "Quit Anyway" would wait like the other button.
            state.exports.cancelExport()
            return NSApplication.shared.terminate(nil)
        }

        Task {
            await state.exports.waitForExportToFinish()
            NSApplication.shared.terminate(nil)
        }
    }

    /// The Discard row's red title, built with `NSColor` so the color survives the tray bridge.
    private static let discardTitle = AttributedString(NSAttributedString(
        string: "Discard Recording…", attributes: [.foregroundColor: NSColor.systemRed]))

    /// docs/06 recording item 9: discarding confirms first — the safe choice is the default, so a
    /// reflexive Return can't destroy a take — then drops the file and returns to Ready.
    private func discardRecording() {
        guard state.session.isActive else { return }

        // Keeping is first, so Return keeps — a reflexive press can't destroy a take.
        guard !Self.confirm(
            "Discard this recording?", "This take will be deleted and can't be recovered.",
            first: "Keep Recording", second: "Discard", secondIsDestructive: true)
        else { return }

        Task { await state.discard() }
    }
}

/// Runs `refresh` once per menu open. `.task` covers the first appearance (no dependency on
/// subscription timing); `didBeginTracking` covers every reopen (which `.task` doesn't re-fire
/// for). `refresh` is idempotent — it publishes nothing when nothing changed — so the overlap
/// on the first open is harmless.
private struct RefreshOnMenuOpen: ViewModifier {
    let refresh: () -> Void

    func body(content: Content) -> some View {
        content
            .task { refresh() }
            .onReceive(NotificationCenter.default.publisher(
                for: NSMenu.didBeginTrackingNotification)) { _ in refresh() }
    }
}

private extension QualityPreset {
    /// docs/06 item 7 names these Efficient / Balanced / High; the raw values are the CLI's.
    var menuTitle: String {
        switch self {
        case .efficient: "Efficient"
        case .balanced: "Balanced"
        case .high: "High"
        }
    }
}
