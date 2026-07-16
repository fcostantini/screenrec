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
            .task { await refreshWhileOpen() }

        Divider()

        Button("Start Recording") { Task { await state.start() } }
            .disabled(state.readiness != .ready)

        Divider()

        // A `Picker` in menu content renders as docs/06 items 5–7 ask: a submenu with a
        // checkmark on the current entry. An explicit `Menu` forced `.inline` adds separators.
        Picker("Display", selection: $state.selectedDisplayID) {
            ForEach(state.displays) { screen in
                Text(screen.name).tag(CGDirectDisplayID?.some(screen.id))
            }
        }

        Picker("Microphone", selection: $state.selectedMicrophoneID) {
            Text("None").tag(String?.none)
            ForEach(state.microphones, id: \.uniqueID) { device in
                Text(device.name).tag(String?.some(device.uniqueID))
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
        // gives no access to `NSMenuItem.indentationLevel` — hence the accessibility label.
        ForEach(state.recentRecordings, id: \.self) { url in
            Button("    \(url.lastPathComponent)") { Finder.reveal(url) }
                .accessibilityLabel(url.lastPathComponent)
        }
    }

    // MARK: - Recording / paused (docs/06 items 1–7)

    @ViewBuilder private var recordingItems: some View {
        Text("\(MenuHeader.elapsed(state.elapsedSeconds)) — "
             + MenuHeader.recordingDetail(bytes: state.recordedBytes))
            .task { await refreshWhileOpen() }

        Divider()

        if state.isPaused {
            Button("Resume") { Task { await state.resume() } }
        } else {
            Button("Pause") { Task { await state.pause() } }
        }
        Button("Stop & Save") { Task { await state.stop() } }

        Divider()

        if let failure = state.lastFailure {
            Text(failure)
        } else if let microphone = state.activeMicrophoneName {
            Text("\(microphone) · separate track")
        }

        // docs/06: the pickers are hidden while recording, not disabled — this row says why.
        Text("Sources locked while recording")
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

    /// Refreshes on open, then ticks the elapsed clock at 1 Hz while the menu is up. SwiftUI
    /// tears down menu content on close, so cancellation delivers docs/06's "no timers while
    /// closed".
    private func refreshWhileOpen() async {
        state.refreshRecentRecordings()
        if !state.isSessionActive {
            state.refreshSources(displays: DisplayOption.liveScreens())
        }
        while !Task.isCancelled {
            state.refreshProgress()
            try? await Task.sleep(for: .seconds(1))
        }
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
