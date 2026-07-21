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

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.isSessionActive {
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

        exportStatusRow
        lastReplayRow

        Button("Start Recording") { Task { await state.start() } }
            .disabled(state.readiness != .ready)

        replayControls

        Divider()

        // A `Picker` in menu content renders as docs/06 items 5–7 ask: a submenu with a
        // checkmark on the current entry. An explicit `Menu` forced `.inline` adds separators.
        //
        // Source (docs/06 item 5, M7-T2): screens above the divider, running apps below — the
        // Microphone submenu's shape. A picked app that isn't running stays listed, dimmed and
        // checkmarked, so the pick is visible without lying (its Start fails loud instead).
        Picker("Source", selection: $state.sourceChoice) {
            ForEach(state.displays) { screen in
                Text(state.displays.count == 1 ? "Entire Screen" : "Entire Screen (\(screen.name))")
                    .tag(SourceChoice.display(screen.id))
            }
            Divider()
            ForEach(state.capturableApps, id: \.bundleID) { app in
                Text(app.name).tag(SourceChoice.app(bundleID: app.bundleID))
            }
            if let missing = state.missingPickedApp {
                Text("\(missing.name) (not running)")
                    .tag(SourceChoice.app(bundleID: missing.bundleID))
                    .disabled(true)
            }
        }

        // Reads through `presentMicrophonePreference`: the checkmark sits on None while a picked
        // device is away, without forgetting the pick. Writes are real user picks. Automatic
        // (docs/06 item 6) follows the system default at capture start.
        Picker("Microphone", selection: Binding(
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

        Picker("Quality", selection: $state.quality) {
            ForEach(QualityPreset.allCases, id: \.self) { preset in
                Text(preset.menuTitle).tag(preset)
            }
        }

        Divider()

        Button("Open Recordings Folder — \(MenuHeader.recordingsFolder(state.outputDirectory))") {
            Finder.open(state.outputDirectory)
        }
        // Indented under the folder above. The indent is in the title because a SwiftUI menu
        // gives no access to `NSMenuItem.indentationLevel` — hence the accessibility label. Each
        // row is a submenu (M10-T2): reveal, or export a shareable MP4.
        ForEach(state.recentRecordings, id: \.self) { url in
            Menu("    \(url.lastPathComponent)") { fileActions(url) }
                .accessibilityLabel(url.lastPathComponent)
        }
    }

    // MARK: - Recording / paused (docs/06 items 1–7)

    @ViewBuilder private var recordingItems: some View {
        // Header values stamp per open and hold: a publish rebuilds the open menu's AppKit
        // rows and garbles hover (M6-T10), so nothing may tick while it's up.
        Text("\(MenuHeader.elapsed(state.elapsedSeconds)) — "
             + MenuHeader.recordingDetail(bytes: state.recordedBytes))
            .modifier(RefreshOnMenuOpen(refresh: refreshAtOpen))

        Divider()

        exportStatusRow
        lastReplayRow

        if state.isPaused {
            Button("Resume") { Task { await state.resume() } }
        } else {
            Button("Pause") { Task { await state.pause() } }
        }
        Button("Stop & Save") { Task { await state.stop() } }

        Divider()

        if let failure = state.lastFailure {
            Text(failure)
        } else {
            // docs/06 recording item 5 (M7-T2): an app-scoped recording names its subject.
            if let app = state.activeAppName {
                Text("Recording \(app) only")
            }
            if let microphone = state.activeMicrophoneName {
                Text("\(microphone) · separate track")
            }
        }

        replayControls

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

    /// The MP4 export's in-menu signal (M10-T2), shared by both menus: an "Exporting…" row while
    /// one runs (stamped at open — nothing may tick into an open menu, M6-T10), then a receipt
    /// that reveals the `.mp4`. The `.mov`-only recents list never shows the export, so this is
    /// its pointer.
    @ViewBuilder private var exportStatusRow: some View {
        if let name = state.exportInProgress {
            Text("Exporting \(name)…")
            Divider()
        } else if let last = state.lastExport {
            Button(last.menuTitle) { Finder.reveal(last.url) }
            Divider()
        }
    }

    /// The per-file submenu shared by recents and the replay receipt: reveal in Finder, or derive
    /// a shareable MP4 / looping GIF (blocked while one export already runs — one at a time).
    @ViewBuilder private func fileActions(_ url: URL) -> some View {
        Button("Reveal in Finder") { Finder.reveal(url) }
        Button("Export as MP4") { state.exportToMP4(url) }
            .disabled(state.exportInProgress != nil)
        Button("Save as GIF") { state.exportToGIF(url) }
            .disabled(state.exportInProgress != nil)
    }

    /// Arm toggle + save row, shared by both menus (docs/06 idle item 3 / recording item 5:
    /// arming mid-recording attaches to the live stream, disarming detaches; the recording is
    /// unaffected). The readiness gate also guards a permission revoked mid-recording.
    @ViewBuilder private var replayControls: some View {
        Toggle("Arm Instant Replay", isOn: $state.isReplayArmed)
            .disabled(state.readiness != .ready && !state.isReplayArmed)
        if state.isReplayArmed {
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

    /// Always a button, never inert text: docs/06 draws it disabled outside blocking conditions,
    /// but notifications don't block, so `needsOnboarding` goes false and a user who dismissed
    /// the prompt would have no route back to the setup window. Auto-open still only fires on a
    /// blocking condition (docs/06 item 1).
    private var idleHeader: some View {
        Button("ScreenRec — \(MenuHeader.idleStatus(state.readiness))") { showOnboarding() }
    }

    private func showOnboarding() {
        openWindow(id: onboardingWindowID)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Opens Settings; see App.swift for why it's a plain `Window`.
    private func showSettings() {
        openWindow(id: settingsWindowID)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Lifecycle

    /// Re-reads sources/recents/progress once per menu open. Each callee assigns only on a real
    /// change, so a no-op reopen publishes nothing and the open menu isn't rebuilt (M6-T10).
    private func refreshAtOpen() {
        state.refreshRecentRecordings()
        if !state.isSessionActive {
            state.refreshSources(displays: DisplayOption.liveScreens())
            // Async because SCShareableContent takes ~a second; on the first open the app rows
            // land a beat late, like the recents. Publishes only on a real change.
            Task { await state.refreshCapturableApps() }
        }
        state.refreshProgress()
    }

    /// docs/06 item 12: quitting mid-recording confirms, then finalizes before exit (ADR-007).
    private func quit() {
        guard state.isSessionActive else { return NSApplication.shared.terminate(nil) }

        let alert = NSAlert()
        alert.messageText = "Stop recording and quit?"
        alert.informativeText = "Your recording will be saved first."
        alert.addButton(withTitle: "Stop & Quit")
        alert.addButton(withTitle: "Keep Recording")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            await state.stopAndWaitForFinalize()
            NSApplication.shared.terminate(nil)
        }
    }

    /// The Discard row's red title, built with `NSColor` so the color survives the tray bridge.
    private static let discardTitle = AttributedString(NSAttributedString(
        string: "Discard Recording…", attributes: [.foregroundColor: NSColor.systemRed]))

    /// docs/06 recording item 9: discarding confirms first — the safe choice is the default, so a
    /// reflexive Return can't destroy a take — then drops the file and returns to Ready.
    private func discardRecording() {
        guard state.isSessionActive else { return }

        let alert = NSAlert()
        alert.messageText = "Discard this recording?"
        alert.informativeText = "This take will be deleted and can't be recovered."
        alert.addButton(withTitle: "Keep Recording")   // default (Return) — the safe choice
        alert.addButton(withTitle: "Discard").hasDestructiveAction = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }

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
