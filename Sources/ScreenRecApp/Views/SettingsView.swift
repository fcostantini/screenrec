import AppCore
import AppKit
import RecorderCore
import SwiftUI

/// The Settings window (docs/06 "Settings window"). Three rows: where recordings go, and the two
/// knobs that shape them. Replay settings arrive with M5 and launch-at-login with M6 — neither
/// has anything to act on yet.
struct SettingsView: View {
    @Bindable var state: AppState

    /// Set when a chosen folder can't be written to. docs/06 and G4 §5.4 both want this said
    /// **at selection**, not discovered at record time as an opaque "invalid parameter" (02 §2).
    @State private var folderProblem: String?

    var body: some View {
        Form {
            LabeledContent("Output folder") {
                HStack(spacing: 8) {
                    // The path as the user thinks of it — `~/Movies`, not /Users/you/Movies.
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private var abbreviatedOutputPath: String {
        (state.outputDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    /// Picks a folder and preflights it immediately.
    ///
    /// The preflight is `OutputLocation.preflight` — written back in M0-T4, with copy that
    /// already says "Choose a different folder in Settings." It probes *write* access rather
    /// than mere existence, which is the whole point: Desktop/Documents/Downloads exist and are
    /// readable while still refusing writes without the Files & Folders grant, and that refusal
    /// surfaces from SCK as "invalid parameter" hours later if nobody checks here (02 §2).
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
            // Keep the old folder. Accepting one we can't write to would trade a message the
            // user is reading right now for a failed recording later.
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
