import AVKit
import SwiftUI

/// The clip the Preview window plays. `WindowPresenter` holds it rather than `AppState`: watching
/// a file derives nothing, so it is no part of the export state `trimTarget` lives in.
@MainActor @Observable
final class PreviewTarget {
    private(set) var url: URL?
    /// Changes when another clip is asked for; a rename of the one playing leaves it alone.
    private(set) var clip = 0
    /// Counts presses of `Play`, so one on the clip already open still reaches the window.
    private(set) var plays = 0

    func play(_ url: URL) {
        if url != self.url {
            self.url = url
            clip += 1
        }
        plays += 1
    }

    func renamed(to url: URL) {
        self.url = url
    }
}

/// Where and how large the Preview window opens (docs/06 "Preview window").
enum PreviewLayout {
    /// The share of the screen's usable area the window may open at.
    private static let screenFraction = 0.7
    static let captionHeight: CGFloat = 30
    /// The picture's floor — the Trim preview's.
    static let minimumPicture = CGSize(width: 480, height: 300)

    /// The clip's own shape, as large as fits the screen's share beside the caption row and
    /// never past a point per pixel. The floor wins over the shape; the player letterboxes.
    static func pictureSize(clip: CGSize?, visible: CGSize) -> CGSize {
        guard let clip, clip.width > 0, clip.height > 0 else { return minimumPicture }
        let box = CGSize(
            width: visible.width * screenFraction,
            height: visible.height * screenFraction - captionHeight)
        let scale = min(1, box.width / clip.width, box.height / clip.height)
        return CGSize(
            width: max(minimumPicture.width, (clip.width * scale).rounded()),
            height: max(minimumPicture.height, (clip.height * scale).rounded()))
    }

    static func contentSize(clip: CGSize?, visible: CGSize) -> CGSize {
        let picture = pictureSize(clip: clip, visible: visible)
        return CGSize(width: picture.width, height: picture.height + captionHeight)
    }

    /// A window of `size` hung from the top-left the user last left it at, slid back inside
    /// `visible` where it would run off: the size may not be the one it had there.
    static func frame(topLeft: CGPoint, size: CGSize, visible: CGRect) -> CGRect {
        let x = min(max(topLeft.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        let top = max(min(topLeft.y, visible.maxY), min(visible.maxY, visible.minY + size.height))
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}

/// The Preview window (M43-T1, docs/06 "Preview window"): a recording to watch, driven from the
/// keyboard. The picture, transport and letterbox are `AVPlayerView`'s; the window adds the keys.
struct PreviewView: View {
    /// How the key monitor knows this window; its title is the clip's name.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("preview")
    private static let caption = "Space to play or pause · ←/→ a frame · ⇧←/⇧→ a second"
    private static let unplayable = "This recording can't be played."

    let target: PreviewTarget
    /// Closes the window. `@Environment(\.dismiss)` does nothing inside a plain `NSWindow`.
    let onClose: () -> Void

    @State private var player: AVPlayer?
    /// `PreviewTarget.clip` as loaded, or nil with nothing loaded.
    @State private var loadedClip: Int?
    @State private var durationSeconds = 0.0
    @State private var cannotPlay = false
    @State private var keyMonitor: Any?

    private var transport: PlayerTransport? {
        player.map { PlayerTransport(player: $0, duration: durationSeconds) }
    }

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(
                    minWidth: PreviewLayout.minimumPicture.width, maxWidth: .infinity,
                    minHeight: PreviewLayout.minimumPicture.height, maxHeight: .infinity)

            Text(Self.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PreviewLayout.captionHeight)
        }
        .onAppear { show() }
        .onChange(of: target.plays) { show() }
        .onDisappear { unload() }
    }

    @ViewBuilder private var picture: some View {
        if let player, !cannotPlay {
            PlayerView(player: player, controlsStyle: .inline)
        } else {
            ZStack {
                Color.black
                if cannotPlay { Text(Self.unplayable).foregroundStyle(.white) }
            }
        }
    }

    /// `Play` on the clip already loaded plays it; on another, loads that one.
    private func show() {
        guard target.clip != loadedClip else { transport?.play(); return }
        load()
    }

    /// Starts the clip playing (docs/06). A load superseded by another clip is ignored.
    private func load() {
        let clip = target.clip
        loadedClip = clip
        player?.pause()
        durationSeconds = 0
        cannotPlay = false
        guard let url = target.url else { player = nil; return }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        startKeyMonitor()
        newPlayer.play()
        Task {
            // An empty or torn file reports itself unplayable here; nothing later would say so.
            let playable = (try? await item.asset.load(.isPlayable)) ?? false
            let duration = (try? await item.asset.load(.duration).seconds) ?? 0
            guard loadedClip == clip else { return }
            cannotPlay = !playable
            durationSeconds = duration.isFinite ? max(0, duration) : 0
        }
    }

    /// A player goes on playing behind a closed window unless it is stopped (measured in Trim:
    /// 13 s of playback across a 10 s closed window).
    private func unload() {
        PlaybackKeyMonitor.remove(keyMonitor)
        keyMonitor = nil
        player?.pause()
        player = nil
        loadedClip = nil
    }

    private func startKeyMonitor() {
        PlaybackKeyMonitor.remove(keyMonitor)
        keyMonitor = PlaybackKeyMonitor.install(
            .preview, for: { $0.identifier == Self.windowIdentifier }, perform: perform)
    }

    private func perform(_ command: PlaybackCommand) {
        switch command {
        case .togglePlayback: transport?.togglePlayback()
        case .stepFrames(let count): transport?.step(byFrames: count) { transport }
        case .nudgeSeconds(let seconds): transport?.nudge(bySeconds: seconds)
        case .close: onClose()
        }
    }
}
