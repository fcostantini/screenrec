import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// Marks name a position **in the file**, so the only interesting case is a take that has been
/// paused: wall clock and recorded time diverge there, and a mark that used the wrong one lands
/// somewhere the user never was (M20-T1).
@MainActor
@Suite struct MarkTests {

    private func makeState() -> AppState {
        AppState(defaults: UserDefaults(suiteName: "marks-tests-\(UUID().uuidString)")!)
    }

    /// A session model whose clock has already run for `seconds`, still running as of `now`.
    private func recording(for seconds: TimeInterval, now: Date) -> SessionModel {
        let session = SessionModel()
        session.apply(.started)
        session.setClockForTesting(
            RecordingClock(accumulated: 0, runningSince: now.addingTimeInterval(-seconds)))
        return session
    }

    @Test func aMarkNamesRecordedTimeNotWallClock() {
        // The take: 20 s recorded, paused for 30, then 6 s more. Wall clock says 56; the file is
        // 26 long, and that is where the mark belongs.
        let now = Date()
        let session = SessionModel()
        session.apply(.started)
        session.setClockForTesting(RecordingClock(accumulated: 20, runningSince: nil))  // paused
        session.apply(.resumed)
        session.setClockForTesting(
            RecordingClock(accumulated: 20, runningSince: now.addingTimeInterval(-6)))

        let at = session.addMark(now: now)
        #expect(at != nil)
        #expect(abs((at ?? 0) - 26) < 0.01, "marked at \(at ?? -1), expected the recorded 26 s")
    }

    @Test func marksAreOrderedAndAccumulate() {
        let now = Date()
        let session = recording(for: 10, now: now)
        session.addMark(now: now)
        session.addMark(now: now.addingTimeInterval(5))
        session.addMark(now: now.addingTimeInterval(9))

        #expect(session.marks.count == 3)
        #expect(session.marks == session.marks.sorted())
        #expect(abs(session.marks[0] - 10) < 0.01)
        #expect(abs(session.marks[2] - 19) < 0.01)
    }

    @Test func aPausedTakeDeclinesTheMark() {
        // Every press while paused would land on the same frozen timestamp — five marks on one
        // frame is worse than none (M20-T1 ruling B).
        let session = SessionModel()
        session.apply(.started)
        session.apply(.paused)
        #expect(session.addMark() == nil)
        #expect(session.marks.isEmpty)
    }

    @Test func anIdleAppHasNothingToMark() {
        let session = SessionModel()
        #expect(session.addMark() == nil)
        #expect(session.marks.isEmpty)
    }

    @Test func marksDieWithTheirTake() {
        // Until M20-T2 gives them a home, a mark belongs to the session that made it — carrying
        // them into the next take would attach one recording's notes to another's frames.
        let now = Date()
        let session = recording(for: 8, now: now)
        session.addMark(now: now)
        #expect(!session.marks.isEmpty)
        session.clear()
        #expect(session.marks.isEmpty)
    }

    // MARK: - What the menu says

    @Test func theMenuRowCountsMarksAndNamesTheLast() {
        let state = makeState()
        #expect(state.marksMenuLabel == nil)          // no marks ⇒ no row

        let now = Date()
        state.session.apply(.started)
        state.session.setClockForTesting(
            RecordingClock(accumulated: 0, runningSince: now.addingTimeInterval(-65)))
        state.session.addMark(now: now)
        #expect(state.marksMenuLabel == "1 mark · last at 1:05")

        state.session.addMark(now: now.addingTimeInterval(10))
        #expect(state.marksMenuLabel == "2 marks · last at 1:15")
    }
}
