import AVFoundation
import Foundation
import Testing
@testable import RecorderCore

/// The filmstrip's sample points (M24-T4), plus the one property of the stream itself that a
/// consumer cannot survive losing: that it **ends**. Where the strip looks is decided here; a wrong
/// answer makes it useless without failing anything.
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

    // MARK: - The stream terminates (M30-T2)

    /// The property the counting race destroys: every requested index arrives **and the stream
    /// finishes**. A lost decrement never reaches zero, so `continuation.finish()` never fires and a
    /// consumer's `for await` never returns — `TrimView`'s strip and `BarDetector`'s crop scan both.
    ///
    /// ⚠️ It cannot *prove* the race is gone: nothing here can force two callbacks to land at once.
    /// It fails loudly if the counting logic breaks, which is the regression guard this file has
    /// never had — `stream` was untested entirely.
    ///
    /// Bounded rather than open-ended, per M15-T1: a regression must **fail** this test, not hang
    /// the run, and "the stream never finishes" is exactly a hang.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_HW_ENCODE_TESTS"] == "1"))
    func yieldsEveryRequestedFrameAndThenFinishes() async throws {
        let source = try await makeVideoOnlyMovie(frames: 90)   // 3 s at 30 fps
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let count = 16
        let times = FilmstripThumbnails.times(count: count, duration: duration)

        let seen: Set<Int>? = await withTaskGroup(of: Set<Int>?.self) { group in
            group.addTask {
                var indices: Set<Int> = []
                for await frame in FilmstripThumbnails.stream(
                    for: asset, times: times, maxPixels: 60) {
                    indices.insert(frame.index)
                }
                return indices          // reached only because the stream finished
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil              // the stream never finished
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        #expect(seen != nil, "the filmstrip stream never finished within 20 s")
        #expect(seen?.count == count)
        #expect(seen == Set(0..<count))
    }
}
