import AppCore
import AppKit
import RecorderCore
import SwiftUI

/// The status item's menu (docs/06 "Menu — idle state" / "Menu — recording state").
///
/// The menu is built fresh each time it opens, which is also when the state behind it is
/// refreshed: docs/06 wants this current on open and silent while closed, so everything here
/// pulls (`.task`) rather than subscribing to timers that would tick behind a closed menu for
/// the length of a 90-minute recording.
struct MenuView: View {
    @Bindable var state: AppState

    var body: some View {
        if state.isSessionActive {
            recordingItems
        } else {
            idleItems
        }
        Divider()
        Button("Quit") { quit() }
            .keyboardShortcut("q")
    }

    // MARK: - Idle (docs/06 items 1–10)

    @ViewBuilder private var idleItems: some View {
        // Header. docs/06 asks for a right-aligned status against a "ScreenRec" title; a
        // `.menu`-style MenuBarExtra renders its rows through AppKit and keeps only the text,
        // so one label is what the platform actually allows here.
        //
        // The refresh hangs off the header rather than off a `Group` around the whole menu: a
        // Group hands its modifiers to *each* child, so a `.task` there starts one polling loop
        // per top-level row instead of one per opening.
        Text("ScreenRec — \(MenuHeader.idleStatus(state.readiness))")
            .task { await refreshWhileOpen() }

        Divider()

        Button("Start Recording") { Task { await state.start() } }
            .disabled(state.readiness != .ready)

        Divider()

        // A `Picker` in menu content renders as exactly what docs/06 items 5–7 ask for: a
        // submenu with a checkmark on the current entry. Wrapping it in an explicit `Menu` and
        // forcing `.inline` instead adds stray separators around the group — closer in code to
        // the spec's wording, further from it on screen.
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

        Button("Open Recordings Folder") { Finder.open(state.outputDirectory) }
        // Indented so the files read as belonging under the folder above them rather than as
        // three more commands. The indent is in the title because a SwiftUI menu gives no access
        // to `NSMenuItem.indentationLevel` — hence the explicit accessibility label, so VoiceOver
        // announces the filename and not the padding.
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

        // docs/06: the pickers are *hidden* while recording, not disabled-but-present — so this
        // row is the only thing that says why they're gone.
        Text("Sources locked while recording")
    }

    // MARK: - Lifecycle

    /// Refreshes on open, then ticks the elapsed clock at 1 Hz for as long as the menu is up.
    /// SwiftUI builds menu content when the menu opens and tears it down when it closes, so this
    /// task's cancellation is what delivers docs/06's "no timers while closed" — the clock stops
    /// existing rather than merely being ignored.
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

    /// docs/06 item 12: quitting mid-recording confirms, then finalizes before exit — never
    /// abandon a writer.
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
