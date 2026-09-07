/// Whether moving the playhead leaves the Trim preview playing (M38-T1).
///
/// Navigation is not a transport command: ←/→, ⇧←/⇧→ and a filmstrip click all funnel through one
/// `seek`, and none of them should decide whether the clip is running. The exception is the end,
/// where resuming plays nothing and would leave the button saying `Pause` over a stopped clip.
enum TrimSeek {

    /// How close to the end counts as the end. `AVPlayer` stops when it reaches it, so a seek that
    /// lands inside this has nothing left to play.
    private static let endTolerance = 0.05

    /// Whether `seconds` is the end of a clip of `duration` — also what `togglePlayback` restarts
    /// from, so the two can't drift.
    static func isAtEnd(_ seconds: Double, duration: Double) -> Bool {
        seconds >= duration - endTolerance
    }

    static func keepsPlaying(wasPlaying: Bool, landingAt seconds: Double, duration: Double) -> Bool {
        wasPlaying && !isAtEnd(seconds, duration: duration)
    }
}
