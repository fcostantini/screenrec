import Testing
@testable import RecorderCore

@Suite struct KeyframeIndexTests {

    @Test func statesBothTimesWhenTheCutMovesBack() {
        // The whole point of the task: the number, not the caveat. The old copy warned that the
        // in-point "snaps to the nearest keyframe" and never said where.
        #expect(KeyframeIndex.cutDescription(requested: 4, actual: 3) == "In 0:04 → cuts at 0:03")
    }

    @Test func saysNothingWhenTheInPointIsAlreadyAKeyframe() {
        // A caveat with nothing to warn about is noise — and it would render on most short clips,
        // training the user to ignore the one case that matters.
        #expect(KeyframeIndex.cutDescription(requested: 4, actual: 4) == nil)
    }

    @Test func ignoresASubFrameDifference() {
        // Sync samples don't land on whole seconds, so an exact match is the wrong test: a 10 ms
        // gap is not something to warn about, and would show as "0:04 → cuts at 0:04".
        #expect(KeyframeIndex.cutDescription(requested: 4.0, actual: 3.99) == nil)
        #expect(KeyframeIndex.cutDescription(requested: 4.0, actual: 3.90) != nil)
    }

    @Test func reportsGapsLongerThanTheKeyframeInterval() {
        // Measured 3.37 s back from a 61 s in-point: capture is frame-on-change, so a static
        // stretch emits no frames and therefore no keyframes. The 2 s setting caps encoded frames,
        // not wall clock — the copy must be able to state a gap of any size.
        #expect(KeyframeIndex.cutDescription(requested: 61, actual: 57.63)
            == "In 1:01 → cuts at 0:57")
    }

    @Test func timecodeMatchesTheTrimWindowsFormat() {
        #expect(KeyframeIndex.timecode(0) == "0:00")
        #expect(KeyframeIndex.timecode(9.9) == "0:09")     // floors, never rounds a cut forward
        #expect(KeyframeIndex.timecode(61) == "1:01")
        #expect(KeyframeIndex.timecode(600) == "10:00")
    }
}
