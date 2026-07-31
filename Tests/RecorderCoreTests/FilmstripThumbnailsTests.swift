import Foundation
import Testing
@testable import RecorderCore

/// The filmstrip's sample points (M24-T4). The generator itself is AVFoundation and gets the live
/// leg; this is the part that decides *where* the strip looks, which a wrong answer makes useless
/// without failing anything.
@Suite struct FilmstripThumbnailsTests {

    @Test func samplesTheCentreOfEachSliceSoNeitherEndFallsOffTheClip() {
        // A first sample at 0 is the black leading frame on many takes, and a last at `duration`
        // is past the final sample — both decode to nothing useful.
        let times = FilmstripThumbnails.times(count: 4, duration: 100)
        #expect(times == [12.5, 37.5, 62.5, 87.5])
        #expect(times.allSatisfy { $0 > 0 && $0 < 100 })
    }

    @Test func spreadsEvenlyAndReturnsExactlyTheCountAsked() {
        let times = FilmstripThumbnails.times(count: 16, duration: 129.11)
        #expect(times.count == 16)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        #expect(gaps.allSatisfy { abs($0 - 129.11 / 16) < 0.0001 })
    }

    @Test func aClipTooShortOrUnreadableAsksForNothing() {
        // A zero or non-finite duration is reachable: `AVAsset.duration` is NaN until the first
        // frame starts a session (02 §10), and the window loads before that resolves.
        #expect(FilmstripThumbnails.times(count: 16, duration: 0).isEmpty)
        #expect(FilmstripThumbnails.times(count: 16, duration: .nan).isEmpty)
        #expect(FilmstripThumbnails.times(count: 16, duration: .infinity).isEmpty)
        #expect(FilmstripThumbnails.times(count: 0, duration: 60).isEmpty)
    }

    @Test func aSubSecondClipStillGetsAFullStrip() {
        // Nothing about the strip is per-second — a 0.4 s replay tail should still fill it.
        let times = FilmstripThumbnails.times(count: 16, duration: 0.4)
        #expect(times.count == 16)
        #expect(times.allSatisfy { $0 > 0 && $0 < 0.4 })
    }
}
