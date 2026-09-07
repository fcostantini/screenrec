import Testing

@testable import AppShell

/// Whether moving the playhead leaves the preview playing (M38-T1).
///
/// 🔴 Measured before the fix: `seek(toSeconds:)` paused unconditionally, so every arrow press and
/// every filmstrip click stopped playback — three controls, one funnel, one `pause()`.
@Suite struct TrimSeekTests {

    @Test func movingThePlayheadWhilePlayingLeavesItPlaying() {
        #expect(TrimSeek.keepsPlaying(wasPlaying: true, landingAt: 4, duration: 300))
    }

    @Test func movingThePlayheadWhilePausedLeavesItPaused() {
        #expect(!TrimSeek.keepsPlaying(wasPlaying: false, landingAt: 4, duration: 300))
    }

    @Test func aMoveOntoTheEndDoesNotResumePlaybackThatWouldPlayNothing() {
        #expect(!TrimSeek.keepsPlaying(wasPlaying: true, landingAt: 299.98, duration: 300))
        #expect(!TrimSeek.keepsPlaying(wasPlaying: true, landingAt: 300, duration: 300))
    }

    @Test func theEndIsTheLastFiftyMilliseconds() {
        #expect(TrimSeek.isAtEnd(299.96, duration: 300))
        #expect(!TrimSeek.isAtEnd(299.9, duration: 300))
    }

    @Test func aClipWithNoDurationNeverResumes() {
        #expect(!TrimSeek.keepsPlaying(wasPlaying: true, landingAt: 0, duration: 0))
    }
}
