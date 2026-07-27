import Testing
@testable import RecorderCore

/// M16-T2: the figure the UI quotes for an armed buffer. The model is docs/04 §6.1 — bitrate ×
/// (window + 2 s slack) plus the two PCM rings — so these tests restate that formula rather than
/// pinning numbers the implementation happened to produce.
@Suite struct ReplayFootprintTests {

    // This display's measured capture size; the recorded "~145 MB busy" in docs/04 §6.1 is the
    // video-only half of the 60 s case below.
    private static let width = 4112
    private static let height = 2570

    private func expected(
        width: Int = ReplayFootprintTests.width, height: Int = ReplayFootprintTests.height,
        fps: Int, seconds: Double, mic: Bool
    ) -> Int64 {
        let video = Double(
            BitrateModel.averageBitrate(width: width, height: height, frameRate: fps, preset: .balanced)) / 8
        let audio = Double(
            ReplayFootprint.systemAudioBytesPerSecond + (mic ? ReplayFootprint.microphoneBytesPerSecond : 0))
        return Int64(((video + audio) * (seconds + 2)).rounded())
    }

    @Test(arguments: [5.0, 60.0, 300.0, 900.0])
    func matchesTheDocumentedFormulaAcrossTheSliderRange(seconds: Double) {
        for fps in [30, 60] {
            for mic in [true, false] {
                #expect(ReplayFootprint.estimatedBytes(
                    width: Self.width, height: Self.height, frameRateCap: fps,
                    seconds: seconds, includesMicrophone: mic)
                    == expected(fps: fps, seconds: seconds, mic: mic))
            }
        }
    }

    @Test func theDefaultWindowLandsOnTheDocumentedFigure() {
        // docs/04 §6.1 records ~145 MB busy for the video ring at 60 s; the audio rings add ~36 MB.
        let bytes = ReplayFootprint.estimatedBytes(
            width: Self.width, height: Self.height, frameRateCap: 60, seconds: 60,
            includesMicrophone: true)
        #expect(bytes > 180_000_000 && bytes < 186_000_000)
        #expect(ReplayFootprint.formatted(bytes).contains("180"))
    }

    @Test func micOffDropsOnlyTheMicRing() {
        let with = ReplayFootprint.estimatedBytes(
            width: Self.width, height: Self.height, frameRateCap: 60, seconds: 60, includesMicrophone: true)
        let without = ReplayFootprint.estimatedBytes(
            width: Self.width, height: Self.height, frameRateCap: 60, seconds: 60, includesMicrophone: false)
        #expect(with - without == Int64(ReplayFootprint.microphoneBytesPerSecond) * 62)
    }

    @Test func aRegionCostsLessThanTheWholeDisplayItSitsOn() {
        let region = ReplayFootprint.estimatedBytes(
            width: 800, height: 600, frameRateCap: 60, seconds: 60, includesMicrophone: true)
        let display = ReplayFootprint.estimatedBytes(
            width: Self.width, height: Self.height, frameRateCap: 60, seconds: 60, includesMicrophone: true)
        #expect(region < display)
    }

    @Test func quotesNothingRatherThanAMisleadingNumber() {
        // A geometry or window we can't estimate yields 0, which callers render as "no figure".
        #expect(ReplayFootprint.estimatedBytes(
            width: 0, height: 2570, frameRateCap: 60, seconds: 60, includesMicrophone: true) == 0)
        #expect(ReplayFootprint.estimatedBytes(
            width: Self.width, height: Self.height, frameRateCap: 60, seconds: 0,
            includesMicrophone: true) == 0)
        #expect(ReplayFootprint.estimatedBytes(
            width: Self.width, height: Self.height, frameRateCap: 0, seconds: 60,
            includesMicrophone: true) == 0)
    }

    @Test func roundsToTwoSignificantFiguresSoTheEstimateReadsAsOne() {
        #expect(ReplayFootprint.roundedToTwoSignificantFigures(183_133_368) == 180_000_000)
        #expect(ReplayFootprint.roundedToTwoSignificantFigures(2_663_000_000) == 2_700_000_000)
        #expect(ReplayFootprint.roundedToTwoSignificantFigures(8_243_000) == 8_200_000)
        #expect(ReplayFootprint.roundedToTwoSignificantFigures(0) == 0)
    }
}
