import Testing
@testable import RecorderCore

@Suite struct KeyframeIndexTests {

    @Test func namesTheInPointAndTheHiddenSeconds() {
        // The whole point of the task: the number, not a caveat. A lossless trim starts exactly
        // where asked — what it doesn't say is that it carries the seconds before that.
        #expect(KeyframeIndex.leadInDescription(requested: 5, start: 3.88)
            == "Starts exactly at 0:05 · keeps 1.1 s before it inside the file")
    }

    @Test func saysNothingWhenTheInPointIsAlreadyAKeyframe() {
        // Nothing is hidden, so there is nothing to say — and it would otherwise render on most
        // short clips, training the user to ignore the one case that matters.
        #expect(KeyframeIndex.leadInDescription(requested: 4, start: 4) == nil)
    }

    @Test func ignoresASubFrameLeadIn() {
        // Sync samples don't land on whole seconds, so an exact match is the wrong test: 10 ms is
        // not worth a sentence, and would read as "keeps 0.0 s".
        #expect(KeyframeIndex.leadInDescription(requested: 4.0, start: 3.99) == nil)
        #expect(KeyframeIndex.leadInDescription(requested: 4.0, start: 3.90) != nil)
    }

    @Test func reportsLeadInsLongerThanTheKeyframeInterval() {
        // Measured 3.43 s on a 23-minute recording: capture is frame-on-change, so a static stretch
        // emits no frames and therefore no keyframes. The 2 s setting caps encoded frames, not wall
        // clock — the copy must be able to state a lead-in of any size.
        #expect(KeyframeIndex.leadInDescription(requested: 61, start: 57.57)
            == "Starts exactly at 1:01 · keeps 3.4 s before it inside the file")
    }

}
