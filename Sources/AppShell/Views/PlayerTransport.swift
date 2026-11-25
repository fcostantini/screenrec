import AVFoundation
import RecorderCore

/// Play, seek and step on one player — what the Trim and Preview windows' keys and controls drive.
@MainActor
struct PlayerTransport {
    let player: AVPlayer
    /// Zero until the clip's length has loaded; nothing moves the playhead before then.
    let duration: Double
    /// Runs before every seek, the restart in `play` included.
    var willSeek: () -> Void = {}

    /// The playhead, clamped into the clip.
    var currentTime: Double {
        max(0, min(player.currentTime().seconds, duration))
    }

    /// A player still buffering counts: it is on its way to playing.
    private var isRunning: Bool {
        player.timeControlStatus != .paused
    }

    /// A clip sitting at its end restarts, since play would otherwise do nothing.
    func play() {
        if TrimSeek.isAtEnd(currentTime, duration: duration) { seek(toSeconds: 0) }
        player.play()
    }

    func togglePlayback() {
        guard !isRunning else { return player.pause() }
        play()
    }

    /// Never changes whether the clip is running, bar `TrimSeek`'s end-of-clip case (M38-T1).
    /// Zero-tolerance: the playhead lands where asked, not at a keyframe seconds earlier.
    func seek(toSeconds seconds: Double) {
        guard duration > 0 else { return }
        willSeek()
        let target = min(max(seconds, 0), duration)
        let keepsPlaying = TrimSeek.keepsPlaying(
            wasPlaying: isRunning, landingAt: target, duration: duration)
        if !keepsPlaying { player.pause() }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func nudge(bySeconds seconds: Double) {
        seek(toSeconds: currentTime + seconds)
    }

    /// Moves `count` of the source's own frames (`FrameStep`, not `step(byCount:)` — docs/07).
    /// `current` is asked after the walk; the step is dropped if another clip has loaded by then.
    func step(byFrames count: Int, current: @escaping () -> PlayerTransport?) {
        guard duration > 0, let asset = player.currentItem?.asset else { return }
        let from = currentTime
        Task {
            guard let next = await FrameStep.time(in: asset, from: from, by: count),
                  let now = current(), now.player === player
            else { return }
            now.seek(toSeconds: next)
        }
    }
}
