import AVKit
import AppCore
import SwiftUI

/// AppKit's concrete `AVPlayerView`, wrapped — SwiftUI's generic `VideoPlayer` fatal-errors
/// instantiating its metadata in a Command-Line-Tools (no-Xcode) SPM build.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// The Trim window (M10-T4, docs/06 "Trim window" — the first editing surface): a preview to find
/// the moment, Set In/Set Out from the playhead, and Trim & Save. The trim itself is a lossless
/// passthrough copy (`AppState.trim`); this view only picks the range.
struct TrimView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var loadedURL: URL?
    @State private var inSeconds = 0.0
    @State private var outSeconds = 0.0
    @State private var durationSeconds = 0.0

    var body: some View {
        Group {
            if let url = state.trimTarget {
                content(url)
            } else {
                Text("Open a recording from the menu to trim it.")
                    .foregroundStyle(.secondary)
                    .frame(width: 420, height: 120)
            }
        }
        .onAppear { load(state.trimTarget) }
        .onChange(of: state.trimTarget) { load(state.trimTarget) }
    }

    @ViewBuilder private func content(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            if let player {
                PlayerView(player: player)
                    .frame(width: 480, height: 300)
                    .cornerRadius(6)
            }

            HStack {
                Button("Set In") { inSeconds = min(currentTime(), outSeconds) }
                Text("In \(timecode(inSeconds))").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("Out \(timecode(outSeconds))").monospacedDigit().foregroundStyle(.secondary)
                Button("Set Out") { outSeconds = max(currentTime(), inSeconds) }
            }

            HStack {
                Text("Trimmed length ≈ \(timecode(max(0, outSeconds - inSeconds)))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Trim & Save") {
                    state.trim(url, from: inSeconds, to: outSeconds)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(outSeconds - inSeconds < 0.1 || state.exportInProgress != nil)
            }

            Text("Lossless — the streams are copied, so the in-point snaps to the nearest keyframe. "
                + "The original is kept; this saves a new “ trimmed” file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 500)
    }

    /// The playhead, clamped into the clip.
    private func currentTime() -> Double {
        max(0, min(player?.currentTime().seconds ?? 0, durationSeconds))
    }

    /// Rebuilds the player and range for a new target; a superseded async duration load is ignored.
    private func load(_ url: URL?) {
        guard url != loadedURL else { return }
        loadedURL = url
        player?.pause()
        guard let url else { player = nil; return }

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        inSeconds = 0
        outSeconds = 0
        durationSeconds = 0
        Task {
            let duration = (try? await item.asset.load(.duration).seconds) ?? 0
            guard loadedURL == url else { return }
            durationSeconds = duration.isFinite ? max(0, duration) : 0
            outSeconds = durationSeconds
        }
    }

    private func timecode(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
