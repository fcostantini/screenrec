import AppCore
import AppKit
import RecorderCore
import SwiftUI

/// The Settings window (docs/06 "Settings window"): where recordings go, and the two knobs that
/// shape them. Replay (M5) and launch-at-login (M6) have nothing to act on yet.
struct SettingsView: View {
    @Bindable var state: AppState

    /// Set when a chosen folder can't be written to. docs/06 and G4 §5.4 want this said at
    /// selection, not as an opaque "invalid parameter" at record time (02 §2).
    @State private var folderProblem: String?

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

            Section("Instant Replay") {
                Picker("Replay buffer", selection: $state.replaySeconds) {
                    ForEach(Settings.allowedReplaySeconds, id: \.self) { seconds in
                        Text(Self.bufferTitle(seconds)).tag(seconds)
                    }
                }
                LabeledContent("Save replay shortcut") {
                    HotkeyRecorderButton(
                        hotkey: $state.replayHotkey,
                        suspendGlobalHotkey: { _ = state.hotkeyRegistrar?(nil) },
                        restoreGlobalHotkey: {
                            if state.isReplayArmed { _ = state.hotkeyRegistrar?(state.replayHotkey) }
                        })
                }
                Text("Shortcuts must include ⌥ or ⌃."
                    + (state.isReplayArmed
                        ? " Changing the buffer or sources restarts replay from empty." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    /// docs/06's values, spelled the way a human says them.
    private static func bufferTitle(_ seconds: Int) -> String {
        seconds == 120 ? "2 minutes" : "\(seconds) seconds"
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
