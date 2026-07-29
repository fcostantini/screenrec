import AVKit
import AppCore
import RecorderCore
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

/// Holds the Play Range boundary observer. A reference so the observer's own closure can capture
/// it without capturing the view — which would reach the player through `@State` and retain it.
private final class RangeObserver {
    var token: Any?
}

/// The Trim window (M10-T4, docs/06 "Trim window" — the first editing surface): a preview to find
/// the moment, Set In/Set Out from the playhead, and Trim & Save. The trim itself runs through
/// `AppState.trim`; this view picks the range and the mode (M18-T1).
struct TrimView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var loadedURL: URL?
    @State private var inSeconds = 0.0
    @State private var outSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var sourceSize: CGSize?
    @State private var reencodes = false
    /// What a lossless trim would keep before the in-point, or nil when nothing would be hidden.
    @State private var leadInText: String?
    @State private var rangeObserver = RangeObserver()

    /// A range worth acting on; below this, Trim & Save and Play Range are meaningless.
    private var hasRange: Bool { outSeconds - inSeconds >= 0.1 }

    /// What `Export as MP4` will produce (M21-T1). The size is this recording's own, fitted through
    /// the width in Settings; it is left out until the geometry loads rather than quoting a figure
    /// that can't be computed yet (M16-T2).
    private var exportNote: String {
        var profile = "H.264"
        if let sourceSize {
            let fitted = Exporter.fittedSize(
                width: Int(sourceSize.width.rounded()), height: Int(sourceSize.height.rounded()),
                configuration: state.exportConfiguration)
            profile += " \(fitted.width) × \(fitted.height)"
        }
        return "Export as MP4 writes only the range — \(profile), ready to paste into a message."
    }

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
        .onDisappear { unload() }
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
                Button("Set In") { setIn() }
                    .keyboardShortcut("i", modifiers: [])
                Text("In \(Timecode.cutPoint(inSeconds))").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("Out \(Timecode.cutPoint(outSeconds))").monospacedDigit().foregroundStyle(.secondary)
                Button("Set Out") { outSeconds = max(currentTime(), inSeconds) }
                    .keyboardShortcut("o", modifiers: [])
            }

            // Absent on most short clips: only a lossless trim hides anything, and only when the
            // in-point isn't already on a keyframe (M18-T1).
            if let leadInText, !reencodes {
                Text(leadInText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Trimmed length ≈ \(Timecode.cutPoint(max(0, outSeconds - inSeconds)))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Play Range") { playRange() }
                    .disabled(!hasRange)
                Button("Export as MP4") {
                    state.exportToMP4(url, range: ExportRange(start: inSeconds, end: outSeconds))
                    dismiss()
                }
                .disabled(!hasRange || state.exportInProgress != nil)
                Button("Trim & Save") {
                    state.trim(url, from: inSeconds, to: outSeconds,
                               mode: reencodes ? .precise : .lossless)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasRange || state.exportInProgress != nil)
            }

            Toggle("Re-encode — the clip will contain only \(Timecode.cutPoint(inSeconds)) – "
                + "\(Timecode.cutPoint(outSeconds))", isOn: $reencodes)

            Text("Both start exactly where you set them. Lossless copies the streams, so the clip "
                + "also keeps the frames back to the previous keyframe inside the file; re-encoding "
                + "drops them, takes longer and can produce a larger file. The original is kept "
                + "either way; this saves a new “ trimmed” file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(exportNote)
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

    private func setIn() {
        inSeconds = min(currentTime(), outSeconds)
        refreshLeadIn()
    }

    /// Plays only `[in, out]`: seeks to the in-point and pauses again on the way past the out-point.
    /// The seek is zero-tolerance — the preview must start where the trim will, not at a keyframe
    /// up to seconds earlier.
    private func playRange() {
        guard let player else { return }
        stopRangePlayback()
        let observer = rangeObserver
        let out = CMTime(seconds: outSeconds, preferredTimescale: 600)
        observer.token = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: out)], queue: .main
        ) { [weak player] in
            player?.pause()
            if let token = observer.token { player?.removeTimeObserver(token) }
            observer.token = nil
        }
        player.seek(
            to: CMTime(seconds: inSeconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { _ in player.play() }
    }

    /// Ends a range playback in flight. An out-point at the very end of the clip may never be
    /// traversed, so the observer can outlive the playback that installed it.
    private func stopRangePlayback() {
        guard let token = rangeObserver.token else { return }
        player?.removeTimeObserver(token)
        player?.pause()
        rangeObserver.token = nil
    }

    /// Asks the asset where a lossless trim from the in-point would really start keeping frames.
    /// Measured at 0.0–0.9 ms on a 23-minute recording, so it runs on every Set In.
    private func refreshLeadIn() {
        guard let asset = player?.currentItem?.asset, let url = loadedURL else { return }
        let requested = inSeconds
        Task {
            let start = await KeyframeIndex.leadInStart(for: asset, trimmingFrom: requested)
            guard loadedURL == url, inSeconds == requested else { return }  // superseded
            leadInText = start.flatMap {
                KeyframeIndex.leadInDescription(requested: requested, start: $0)
            }
        }
    }

    /// Closing the window does not tear down a `Window` scene's state, so the player would go on
    /// playing — audible, with nothing on screen to stop it (measured: 13 s of playback across a
    /// 10 s closed window). Dropping it here also frees the decode pipeline of a multi-GB source;
    /// `loadedURL` goes with it so reopening the same recording rebuilds instead of resuming.
    private func unload() {
        stopRangePlayback()
        player?.pause()
        player = nil
        loadedURL = nil
    }

    /// Rebuilds the player and range for a new target; a superseded async duration load is ignored.
    private func load(_ url: URL?) {
        guard url != loadedURL else { return }
        stopRangePlayback()
        loadedURL = url
        player?.pause()
        guard let url else { player = nil; return }

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        inSeconds = 0
        outSeconds = 0
        durationSeconds = 0
        sourceSize = nil
        leadInText = nil
        reencodes = false
        Task {
            let asset = item.asset
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            var size: CGSize?
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                size = try? await track.load(.naturalSize)
            }
            guard loadedURL == url else { return }
            durationSeconds = duration.isFinite ? max(0, duration) : 0
            outSeconds = durationSeconds
            sourceSize = size
        }
    }
}
