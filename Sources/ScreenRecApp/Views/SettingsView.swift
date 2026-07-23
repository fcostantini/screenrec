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

    var body: some View {
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

            Toggle("Launch at login", isOn: $state.launchAtLogin)

            Toggle("Show recording time in the menu bar", isOn: $state.showsMenuBarTimer)

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
                Text("Starts recording, or stops and saves the current one, from any app. "
                    + "Must include ⌥ or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Instant Replay") {
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
        .frame(width: 420)
        .fixedSize()
        .onAppear { syncReplayControls() }
        .onChange(of: state.replaySeconds) { syncReplayControls() }
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
