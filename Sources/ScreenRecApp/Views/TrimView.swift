import AVKit
import AppCore
import Carbon.HIToolbox
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

/// Holds the observers the view installs on its player. A reference so an observer's own closure
/// can capture it without capturing the view — which would reach the player through `@State` and
/// retain it.
///
/// Main-queue confined, which is what lets an observer's `@Sendable` closure hold it: the view
/// touches it on the main actor, and every observer here is installed with `queue: .main`.
private final class PlayerObservers: @unchecked Sendable {
    /// The Play Range boundary observer.
    var range: Any?
    /// The periodic observer driving the filmstrip's playhead (M24-T4).
    var playhead: Any?
    /// The Trim window's arrow-key monitor (M24-T4).
    var keys: Any?
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
    @State private var observers = PlayerObservers()
    /// The filmstrip's frames, by slice index — sparse while they arrive (M24-T4).
    @State private var thumbnails: [Int: CGImage] = [:]
    @State private var stripTask: Task<Void, Never>?
    @State private var playhead = 0.0
    /// Crop drawing is a mode: an always-on overlay would swallow `AVPlayerView`'s inline transport
    /// controls, which sit under it (M26-T2).
    @State private var cropping = false
    /// The crop, in source pixels — the shape the exporter takes, so nothing about the preview's
    /// geometry can drift into it. Nil until one is drawn.
    @State private var crop: CropRect?
    /// The drag in flight, in preview coordinates.
    @State private var dragged: CGRect?

    private static let previewSize = CGSize(width: 480, height: 300)
    /// One row of thumbnails across the player's width. 16 measured at 785 ms on a recording,
    /// against 1.8 s for 24 — which is also past the size a screen recording reads at (docs/07).
    private static let stripCount = 16
    private static let stripHeight: CGFloat = 19
    /// Bounds the decoded thumbnail; the cell is 30 pt wide, so this covers a 2× display.
    private static let thumbnailPixels = 80

    /// A range worth acting on; below this, Trim & Save and Play Range are meaningless.
    private var hasRange: Bool { outSeconds - inSeconds >= 0.1 }

    /// What `Export & Copy` will produce (M21-T1). The size is what will really be encoded — the
    /// crop when there is one (M26-T2), else the whole frame — fitted through the width in Settings;
    /// it is left out until the geometry loads rather than quoting a figure that can't be computed
    /// yet (M16-T2).
    private var exportNote: String {
        var profile = "H.264"
        if let sourceSize {
            let fitted = Exporter.fittedSize(
                width: crop?.width ?? Int(sourceSize.width.rounded()),
                height: crop?.height ?? Int(sourceSize.height.rounded()),
                configuration: state.exportConfiguration)
            profile += " \(fitted.width) × \(fitted.height)"
        }
        let written = crop == nil ? "only the range" : "only the range, cropped"
        return "Export & Copy writes \(written) — \(profile) — and puts it on the clipboard. "
            + "⌘V pastes it."
    }

    var body: some View {
        Group {
            if let url = state.exports.trimTarget {
                content(url)
            } else {
                Text("Open a recording from the menu to trim it.")
                    .foregroundStyle(.secondary)
                    .frame(width: 420, height: 120)
            }
        }
        .onAppear { load(state.exports.trimTarget) }
        .onChange(of: state.exports.trimTarget) { load(state.exports.trimTarget) }
        // Unticking is how a crop is discarded: leaving one set but undrawn would crop an export
        // with nothing on screen saying so.
        .onChange(of: cropping) { if !cropping { crop = nil; dragged = nil } }
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
                    .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                    .overlay { if cropping { cropOverlay } }
                    .cornerRadius(6)
            }

            filmstrip
            Text("Click to seek · ←/→ a frame · ⇧←/⇧→ a second")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                Button("Export & Copy") {
                    state.exportAndCopy(
                        url, range: ExportRange(start: inSeconds, end: outSeconds), crop: crop)
                    dismiss()
                }
                // ⌘↩ so the whole loop is keyboard-only (G24): ←/→ to find the moment, I/O to set
                // the range, this to copy it. Return stays on Trim & Save — ADR-015 keeps lossless
                // the default action.
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!hasRange || state.exports.exportInProgress != nil)
                Button("Trim & Save") {
                    state.trim(url, from: inSeconds, to: outSeconds,
                               mode: reencodes ? .precise : .lossless)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                // A trim is an `AVAssetExportSession` — it has no crop, so with one set this button
                // could only ignore it (M26-T2).
                .disabled(!hasRange || state.exports.exportInProgress != nil || crop != nil)
            }

            HStack(spacing: 8) {
                Toggle("Crop — drag on the preview", isOn: $cropping)
                if let crop {
                    Text("\(crop.width) × \(crop.height) px at \(crop.x),\(crop.y)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Reset") { self.crop = nil }
                        .buttonStyle(.link)
                }
            }
            if crop != nil {
                Text("Trim & Save can't crop — clear the crop to use it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

    /// The crop band over the preview (M26-T2): drag to draw, drag again to redraw. The dim is
    /// punched through by the kept rectangle, so the bright area is what the export will hold.
    /// Held in source pixels and converted back for drawing, never the other way round.
    @ViewBuilder private var cropOverlay: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let band = dragged ?? crop.flatMap { rect in
                sourceSize.map {
                    CropGeometry.viewRect(for: rect, sourceSize: $0, viewSize: size)
                }
            }
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.45)
                if let band {
                    Rectangle()
                        .frame(width: band.width, height: band.height)
                        .offset(x: band.minX, y: band.minY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .overlay(alignment: .topLeading) {
                if let band {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: band.width, height: band.height)
                        .offset(x: band.minX, y: band.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { dragged = Self.rect(from: $0.startLocation, to: $0.location) }
                    .onEnded { drag in
                        dragged = nil
                        guard let sourceSize else { return }
                        crop = CropGeometry.crop(
                            fromViewRect: Self.rect(from: drag.startLocation, to: drag.location),
                            sourceSize: sourceSize, viewSize: size)
                    })
        }
        .accessibilityLabel("Crop region")
    }

    /// The rectangle between two drag points, in any direction. Not `CGRect.union`, which treats an
    /// empty rect as absent and would collapse a drag to a point.
    private static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// One row of thumbnails across the take (M24-T4), filling in as they decode. Navigation, not
    /// editing: a click seeks proportionally, so the resolution is the pointer's, not the strip's.
    @ViewBuilder private var filmstrip: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(0..<Self.stripCount, id: \.self) { index in
                    if let image = thumbnails[index] {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * playheadFraction)
                    .shadow(radius: 1)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                seek(toFraction: event.location.x / max(geometry.size.width, 1))
            })
        }
        .frame(height: Self.stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityLabel("Filmstrip")
        .accessibilityValue(Timecode.cutPoint(playhead))
    }

    /// Where the playhead sits along the strip, 0…1.
    private var playheadFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(playhead / durationSeconds, 0), 1)
    }

    /// Exactly one frame — the source's next one, found in the sample table. `step(byCount:)`
    /// assumes a fixed cadence our frame-on-change capture doesn't have (measured: it moved 0.25 s
    /// and landed off every source frame, `FrameStep`).
    private func step(byFrames count: Int) {
        guard let player, let asset = player.currentItem?.asset, let url = loadedURL else { return }
        player.pause()
        let from = currentTime()
        Task {
            guard let next = await FrameStep.time(in: asset, from: from, by: count),
                  loadedURL == url                                   // superseded while walking
            else { return }
            seek(toSeconds: next)
        }
    }

    /// A second either way, for travelling without leaving the keyboard. Zero-tolerance, so the
    /// playhead lands where the label says rather than at a keyframe up to seconds earlier.
    private func nudge(bySeconds seconds: Double) {
        seek(toSeconds: currentTime() + seconds)
    }

    private func seek(toFraction fraction: Double) {
        seek(toSeconds: durationSeconds * min(max(fraction, 0), 1))
    }

    private func seek(toSeconds seconds: Double) {
        guard let player, durationSeconds > 0 else { return }
        player.pause()
        player.seek(
            to: CMTime(seconds: min(max(seconds, 0), durationSeconds), preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
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
        let observers = observers
        let out = CMTime(seconds: outSeconds, preferredTimescale: 600)
        observers.range = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: out)], queue: .main
        ) { [weak player] in
            player?.pause()
            if let token = observers.range { player?.removeTimeObserver(token) }
            observers.range = nil
        }
        player.seek(
            to: CMTime(seconds: inSeconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { _ in player.play() }
    }

    /// Ends a range playback in flight. An out-point at the very end of the clip may never be
    /// traversed, so the observer can outlive the playback that installed it.
    private func stopRangePlayback() {
        guard let token = observers.range else { return }
        player?.removeTimeObserver(token)
        player?.pause()
        observers.range = nil
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
        stopPlayheadObserver()
        stopKeyMonitor()
        // A superseded strip would otherwise keep decoding a multi-GB source behind a closed window.
        stripTask?.cancel()
        stripTask = nil
        player?.pause()
        player = nil
        loadedURL = nil
    }

    /// Claims the arrow keys for the Trim window.
    ///
    /// Not `.keyboardShortcut(.leftArrow, …)`: a bare arrow is not a key equivalent, so it is
    /// delivered as a `keyDown` to the first responder — which is `AVPlayerView`, whose own
    /// handling scrubs (measured: 90 presses moved the playhead **47.7 s**, ~0.53 s each). The
    /// monitor takes the event first and returns nil so the player never sees it. Scoped by window
    /// title, so Settings and the rename alert keep their arrows.
    private func startKeyMonitor() {
        stopKeyMonitor()
        observers.keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == trimWindowTitle else { return event }
            let stepsASecond = event.modifierFlags.contains(.shift)
            switch Int(event.keyCode) {
            case kVK_LeftArrow:
                stepsASecond ? nudge(bySeconds: -1) : step(byFrames: -1)
            case kVK_RightArrow:
                stepsASecond ? nudge(bySeconds: 1) : step(byFrames: 1)
            default:
                return event
            }
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let monitor = observers.keys { NSEvent.removeMonitor(monitor) }
        observers.keys = nil
    }

    /// Drives the strip's playhead. 0.2 s is enough to read as live and assigns to one `@State`,
    /// so it costs a redraw of 16 already-decoded images.
    private func startPlayheadObserver(_ player: AVPlayer) {
        stopPlayheadObserver()
        observers.playhead = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { time in
            // Installed with `queue: .main`, so this is provably on the main actor.
            MainActor.assumeIsolated { playhead = time.seconds.isFinite ? time.seconds : 0 }
        }
    }

    private func stopPlayheadObserver() {
        guard let token = observers.playhead else { return }
        player?.removeTimeObserver(token)
        observers.playhead = nil
    }

    /// Fills the strip as frames arrive (M24-T4) — the first lands in ~80 ms, so the window is
    /// usable long before the last one does.
    private func loadFilmstrip(_ url: URL, asset: AVAsset, duration: Double) {
        stripTask?.cancel()
        thumbnails = [:]
        let times = FilmstripThumbnails.times(count: Self.stripCount, duration: duration)
        guard !times.isEmpty else { return }
        stripTask = Task {
            for await frame in FilmstripThumbnails.stream(
                for: asset, times: times, maxPixels: Self.thumbnailPixels
            ) {
                guard loadedURL == url else { return }   // superseded by another recording
                thumbnails[frame.index] = frame.image
            }
        }
    }

    /// Rebuilds the player and range for a new target; a superseded async duration load is ignored.
    private func load(_ url: URL?) {
        guard url != loadedURL else { return }
        stopRangePlayback()
        loadedURL = url
        player?.pause()
        guard let url else { player = nil; return }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        startPlayheadObserver(newPlayer)
        startKeyMonitor()
        playhead = 0
        thumbnails = [:]
        inSeconds = 0
        outSeconds = 0
        durationSeconds = 0
        sourceSize = nil
        leadInText = nil
        reencodes = false
        // A crop belongs to the clip it was drawn on, so it does not survive the next one — the
        // same rule the range follows.
        cropping = false
        crop = nil
        dragged = nil
        Task {
            let asset = item.asset
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            // `MediaFile.dimensions` instead of loading the track here: it returns a plain size
            // rather than an `AVAssetTrack`, so nothing non-`Sendable` crosses back.
            let size = await MediaFile.dimensions(of: url).map {
                CGSize(width: $0.width, height: $0.height)
            }
            guard loadedURL == url else { return }
            durationSeconds = duration.isFinite ? max(0, duration) : 0
            outSeconds = durationSeconds
            sourceSize = size
            loadFilmstrip(url, asset: asset, duration: durationSeconds)
        }
    }
}
