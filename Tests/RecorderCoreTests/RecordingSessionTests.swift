import Testing
@testable import RecorderCore

/// The finalize fate-matrix (M13-T3): given the end-of-loop state, which branch decides the file's
/// fate. The safety-critical logic — a mis-ordered priority is how a take gets lost — now pure and
/// asserted directly instead of only live-verified.
@Suite struct RecordingSessionTests {

    private func plan(
        discard: Bool = false, startFailure: String? = nil,
        fate: RecordingSession.FileFate? = nil, failedToBeginWriting: Bool = false,
        endReason: EndReason = .userStopped
    ) -> RecordingSession.FinalizePlan {
        RecordingSession.finalizePlan(
            discardRequested: discard, startFailure: startFailure, fate: fate,
            failedToBeginWriting: failedToBeginWriting, endReason: endReason)
    }

    // MARK: the six branches

    @Test func normalFinishIsTheDefault() {
        #expect(plan(endReason: .userStopped) == .finalizeNormal(reason: .userStopped))
        // The end reason rides through — a display unplug still finalizes, just with its cause.
        #expect(plan(endReason: .displayDisconnected) == .finalizeNormal(reason: .displayDisconnected))
    }

    @Test func aStartFailureFailsToStart() {
        #expect(plan(startFailure: "no permission") == .failToStart(message: "no permission"))
    }

    @Test func aDeletedFileFailsUnsalvageably() {
        #expect(plan(fate: .deleted) == .failDeleted)
    }

    @Test func aStrandedFileFinalizesAtItsPath() {
        #expect(plan(fate: .strandedAt("/tmp/moved.partial"), endReason: .displayDisconnected)
            == .finalizeStranded(path: "/tmp/moved.partial", reason: .displayDisconnected))
    }

    @Test func aWriterThatNeverBeganFailsWriteNeverBegan() {
        #expect(plan(failedToBeginWriting: true) == .failWriteNeverBegan)
    }

    @Test func aDiscardRemovesTheFile() {
        #expect(plan(discard: true) == .discard(strandedPath: nil))
    }

    // MARK: priority — the bug-prone part (a mis-order loses or corrupts a take)

    @Test func discardWinsOverEveryOtherFate() {
        // Set alongside every other trigger — a discard still wins (docs/03: "wins over every fate").
        #expect(plan(discard: true, startFailure: "x", fate: .deleted, failedToBeginWriting: true)
            == .discard(strandedPath: nil))
        // And a discard of a stranded take carries the moved path to also remove.
        #expect(plan(discard: true, fate: .strandedAt("/tmp/moved.partial"))
            == .discard(strandedPath: "/tmp/moved.partial"))
    }

    @Test func startFailureBeatsFateAndWriteNeverBegan() {
        #expect(plan(startFailure: "x", fate: .deleted, failedToBeginWriting: true)
            == .failToStart(message: "x"))
        // The consequential pair: fail-to-start beats finalizing a stranded file — "fail beats save".
        #expect(plan(startFailure: "x", fate: .strandedAt("/tmp/moved.partial"))
            == .failToStart(message: "x"))
    }

    @Test func fateBeatsWriteNeverBegan() {
        #expect(plan(fate: .deleted, failedToBeginWriting: true) == .failDeleted)
        #expect(plan(fate: .strandedAt("/tmp/x.partial"), failedToBeginWriting: true)
            == .finalizeStranded(path: "/tmp/x.partial", reason: .userStopped))
    }

    // MARK: message helpers — M6-T3 bar (say what happened AND what to do)

    @Test func deletedMessageSaysItPlainly() {
        #expect(RecordingSession.deletedMessage.contains("deleted"))
    }

    @Test func writeNeverBeganMessageNamesTheFolderAndTheFix() {
        let message = RecordingSession.writeNeverBeganMessage(folder: "Movies")
        #expect(message.contains("Movies"))
        #expect(message.contains("Choose another folder"))
    }

    @Test func strandedFinalizeFailedMessageNamesThePath() {
        #expect(RecordingSession.strandedFinalizeFailedMessage(path: "/tmp/moved.partial")
            .contains("/tmp/moved.partial"))
    }

    @Test func finalizeFailureMessagePointsAtRecovery() {
        // The normal-finish failure (unchanged by M13-T3): a recovered copy appears next launch.
        #expect(RecordingSession.finalizeFailureMessage.contains("recovered"))
    }
}
