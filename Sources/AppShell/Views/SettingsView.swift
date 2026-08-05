import AppCore
import AppKit
import RecorderCore
import SwiftUI

/// The Settings window (docs/06 "Settings window"): output folder, capture knobs, launch-at-login,
/// and the instant-replay buffer and shortcut.
struct SettingsView: View {
    @Bindable var state: AppState

    /// Set when a chosen folder can't be written to. docs/06 and G4 §5.4 want this said at
    /// selection, not as an opaque "invalid parameter" at record time (02 §2).
    @State private var folderProblem: String?

    /// The replay-length slider's in-progress value (M9-T8): snapped to 15 s while dragging and
    /// committed to `state.replaySeconds` only on release, so a drag doesn't resize the armed ring on
    /// every tick. Seeded from the model.
    @State private var draftReplaySeconds: Double = 60
    /// The editable `M:SS` value beside the slider — finer than the 15 s slider steps, typed.
    @State private var replayText = ""

    /// The Settings window's pages (M18-T6). As one `Form` with `.fixedSize()` the window had no
    /// ceiling: it measured 1137 pt against 1260 pt of usable screen, and every new preference made
    /// it worse.
    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case recording = "Recording"
        case replay = "Instant Replay"
        case sharing = "Sharing"

        var id: Self { self }
    }

    @State private var page: Page = .general

    var body: some View {
        VStack(spacing: 0) {
            // A segmented control, not `TabView`: at this width SwiftUI collapses toolbar tabs into
            // a `»` overflow menu, which hides three of the four pages behind a chevron.
            Picker("", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 12)

            switch page {
            case .general: general
            case .recording: recording
            case .replay: instantReplay
            case .sharing: sharing
            }
        }
        .frame(width: 460)
        .fixedSize()
        .onAppear { syncReplayControls() }
        .onChange(of: state.replaySeconds) { syncReplayControls() }
    }

    /// Where files go and what the menu bar shows — plus the build, which M16-T6 put here so
    /// "am I on the build with the fix?" is answerable from inside the app.
    private var general: some View {
        Form {
            LabeledContent("Output folder") {
                HStack(spacing: 8) {
                    Text(abbreviatedOutputPath)
                        .foregroundStyle(.secondary)
                        .truncationMode(.head)          // the tail is the folder they picked
                        .lineLimit(1)
                    Button("Choose…") { chooseFolder() }
                }
            }

            if let folderProblem {
                Text(folderProblem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Launch at login", isOn: $state.launchAtLogin)

            Toggle("Check for new versions", isOn: $state.checksForUpdates)

            Text("Once a day, ScreenRec asks GitHub whether a newer release exists and says so in the menu. It never downloads anything. The request tells GitHub your IP address — turn this off and the app makes no network requests at all.")

                .font(.caption)

                .foregroundStyle(.secondary)

                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show recording time in the menu bar", isOn: $state.showsMenuBarTimer)

            // M16-T5: the meter's twin opt-out. Shown while recording or armed, so a dead mic is
            // visible before a take.
            Toggle("Show input level in the menu bar", isOn: $state.showsMenuBarLevel)


            // M16-T6: ADR-014 hands people a signed .app directly — the version has to be
            // answerable from inside the app.
            Text(state.versionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    /// What a take *is*: its quality and rate, the beat before it, and the shortcuts that start
    /// and pause it.
    private var recording: some View {
        Form {
            Picker("Quality", selection: $state.quality) {
                ForEach(QualityPreset.allCases, id: \.self) { preset in
                    Text(preset.settingsTitle).tag(preset)
                }
            }

            Picker("Frame rate", selection: $state.frameRateCap) {
                ForEach(Settings.allowedFrameRateCaps, id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
            }

            // M9-T4: opt-in, because a start/stop combo is always live (unlike replay's, which fires
            // only while armed). Enabling seeds ⌥⌘S; the recorder pill changes it.
            Toggle("Global start/stop shortcut", isOn: Binding(
                get: { state.recordHotkey != nil },
                set: { state.recordHotkey = $0 ? (state.recordHotkey ?? .recordDefault) : nil }))
            if state.recordHotkey != nil {
                LabeledContent("Start/stop shortcut") {
                    HotkeyRecorderButton(
                        hotkey: Binding(
                            get: { state.recordHotkey ?? .recordDefault },
                            set: { state.recordHotkey = $0 }),
                        accessibilityName: "Start/stop recording shortcut",
                        suspendGlobalHotkey: { _ = state.hotkeyRegistrar?(nil, .toggleRecording) },
                        restoreGlobalHotkey: {
                            if let hk = state.recordHotkey {
                                _ = state.hotkeyRegistrar?(hk, .toggleRecording)
                            }
                        })
                }
                // M24-T2: which ending the combo has. A picker rather than a second shortcut —
                // "Save and copy" keeps the .mov too (ADR-004), so there is nothing to trade
                // per-take, and the menu's shortcut column follows this pick.
                Picker("When it stops", selection: $state.stopHotkeyCopies) {
                    Text("Save").tag(false)
                    Text("Save and copy").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Starts recording, or stops the current one, from any app. "
                    + (state.stopHotkeyCopies
                        ? "It also writes an MP4 and leaves it on the clipboard. "
                        : "")
                    + "Must include ⌥ or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // M12-T6: opt-in, the start/stop twin. Pause the recording mid-demo without opening the
            // menu (which is itself captured). Enabling seeds ⌥⌘P; the recorder pill changes it.
            Toggle("Global pause/resume shortcut", isOn: Binding(
                get: { state.pauseHotkey != nil },
                set: { state.pauseHotkey = $0 ? (state.pauseHotkey ?? .pauseDefault) : nil }))
            if state.pauseHotkey != nil {
                LabeledContent("Pause/resume shortcut") {
                    HotkeyRecorderButton(
                        hotkey: Binding(
                            get: { state.pauseHotkey ?? .pauseDefault },
                            set: { state.pauseHotkey = $0 }),
                        accessibilityName: "Pause/resume recording shortcut",
                        suspendGlobalHotkey: { _ = state.hotkeyRegistrar?(nil, .togglePause) },
                        restoreGlobalHotkey: {
                            if let hk = state.pauseHotkey {
                                _ = state.hotkeyRegistrar?(hk, .togglePause)
                            }
                        })
                }
                Text("Pauses or resumes the current recording from any app. Must include ⌥ or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // M12-T6: a 3-2-1 beat before capture to switch to the target window. The countdown
            // isn't in the recording.
            Toggle("Count in before recording (3-2-1)", isOn: $state.countInEnabled)

            // M21-T3: the one moment the name is still in your head. Off by default — a modal
            // after every stop is the wrong default for the quick takes that are most of them.
            Toggle("Ask for a name when a recording stops", isOn: $state.namesTakeOnStop)
        }
        .formStyle(.grouped)
    }

    private var instantReplay: some View {
        Form {
            LabeledContent("Replay buffer") {
                HStack(spacing: 10) {
                    // Continuous slider (no `step:`, so no tick marks), snapped to 15 s in the
                    // binding; committed on release so a drag while armed resizes the ring once
                    // (via `windowChanged`), not hundreds of times.
                    Slider(value: snappedReplayBinding, in: Self.replayRange) { editing in
                        if !editing { state.replaySeconds = Int(draftReplaySeconds) }
                    }
                    TextField("", text: $replayText)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 54)
                        .onSubmit(commitTypedReplayBuffer)
                }
            }
            // The cost of the window the slider just set (M16-T2) — memory, and ADR-018's
            // deliberate wakefulness. Reads `draftReplaySeconds` so it tracks the drag, not
            // the commit-on-release.
            Text(state.replayBufferCaption(seconds: Int(draftReplaySeconds)))
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Save replay shortcut") {
                HotkeyRecorderButton(
                    hotkey: $state.replayHotkey,
                    accessibilityName: "Save replay shortcut",
                    suspendGlobalHotkey: { _ = state.hotkeyRegistrar?(nil, .saveReplay) },
                    restoreGlobalHotkey: {
                        if state.isReplayArmed {
                            _ = state.hotkeyRegistrar?(state.replayHotkey, .saveReplay)
                        }
                    })
            }
            Text("Shortcuts must include ⌥ or ⌃."
                + (state.isReplayArmed
                    ? " Changing the buffer or sources restarts replay from empty." : ""))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Banner suppression (docs/06 §Notifications): while armed, the screen is captured,
            // so macOS hides banners — ours and other apps'. Name the fix, not the API.
            Text("While replay is armed, macOS hides notification banners — ScreenRec's and other "
                + "apps'. To keep seeing them, turn on \"Allow notifications when mirroring or "
                + "sharing the display\" in System Settings › Notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Notification Settings…") { NotificationSettings.open() }
            .buttonStyle(.link)
            .font(.caption)
        }
        .formStyle(.grouped)
    }

    /// The two derive-a-file formats together — both answer "what comes out when I share this".
    private var sharing: some View {
        Form {
            Section("MP4") {
                Picker("Size", selection: $state.mp4Width) {
                    ForEach(Settings.allowedMP4Widths, id: \.self) {
                        Text(state.mp4SizeLabel(forWidth: $0)).tag($0)
                    }
                }
                Text("Applies to Export as MP4. Height follows the source's aspect. Sizes stop "
                    + "where H.264 does on phones, so the clip still plays where you send it — "
                    + "the weights are rough and depend on what's on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Include the microphone", isOn: $state.exportsIncludeMicrophone)
                Text("Off leaves your narration out of shared clips — the recording still keeps "
                    + "the microphone on its own track, so nothing is lost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("GIF") {
                Picker("Frames per second", selection: $state.gifFPS) {
                    ForEach(Settings.allowedGifFPS, id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Width", selection: $state.gifWidth) {
                    ForEach(Settings.allowedGifWidths, id: \.self) { Text("\($0) px").tag($0) }
                }
                Picker("Maximum length", selection: $state.gifMaxSeconds) {
                    ForEach(Settings.allowedGifMaxSeconds, id: \.self) { Text("\($0) s").tag($0) }
                }
                Text("Applies to Save as GIF. A longer clip is trimmed to its first Maximum length; "
                    + "height follows the source's aspect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// The replay slider's range as `Double`s (M9-T8), kept off the view body so the type-checker
    /// isn't asked to prove the whole expression at once.
    private static let replayRange =
        Double(Settings.replaySecondsRange.lowerBound)...Double(Settings.replaySecondsRange.upperBound)

    /// Snaps the slider to 15 s (M9-T8) without tick marks: the binding rounds every set, so the
    /// thumb lands on 15 s multiples while the slider itself stays continuous (no `step:`).
    private var snappedReplayBinding: Binding<Double> {
        Binding(
            get: { draftReplaySeconds },
            set: { newValue in
                let step = Double(Settings.replaySliderStep)
                let snapped = (newValue / step).rounded() * step
                draftReplaySeconds = min(max(snapped, Self.replayRange.lowerBound),
                                         Self.replayRange.upperBound)
            })
    }

    /// Keeps the slider draft and the typed `M:SS` field in step with the model.
    private func syncReplayControls() {
        draftReplaySeconds = Double(state.replaySeconds)
        replayText = Settings.replayBufferLabel(state.replaySeconds)
    }

    /// Commits a typed value (`M:SS` or seconds); unparseable input reverts the field.
    private func commitTypedReplayBuffer() {
        if let seconds = Settings.parseReplayBuffer(replayText) {
            state.replaySeconds = seconds       // onChange re-syncs the slider and normalizes the text
        } else {
            replayText = Settings.replayBufferLabel(state.replaySeconds)
        }
    }

    private var abbreviatedOutputPath: String {
        (state.outputDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    /// Picks a folder and preflights write access immediately: Desktop/Documents/Downloads are
    /// readable but refuse writes without the Files & Folders grant, which SCK surfaces as
    /// "invalid parameter" much later (02 §2).
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = state.outputDirectory
        panel.prompt = "Choose"
        panel.message = "Where should ScreenRec save recordings?"

        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        switch OutputLocation.preflight(chosen) {
        case .accessible:
            folderProblem = nil
            state.outputDirectory = chosen        // persists + re-reads recent files
        case .inaccessible(let reason):
            // Keep the old folder; accepting an unwritable one defers the failure to record time.
            folderProblem = reason
        }
    }
}

private extension QualityPreset {
    /// docs/06 item 7's names, same as the menu's.
    var settingsTitle: String {
        switch self {
        case .efficient: "Efficient"
        case .balanced: "Balanced"
        case .high: "High"
        }
    }
}
