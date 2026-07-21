import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// docs/06's copy rules as assertions. The rules are the point of the table — "outcome first,
/// cause second, always a playable file" is ADR-007 in UI form, and it's the kind of thing that
/// erodes one well-meaning edit at a time.
@Suite struct RecordingNotificationTests {

    private static let url = URL(fileURLWithPath: "/Movies/Recording 2026-07-15 at 15.24.56.mov")

    /// Every reason a recording can end for, other than the user asking.
    private static let failStops: [EndReason] = [
        .displayDisconnected, .appQuit, .microphoneChanged, .diskAlmostFull, .streamError("-3818"),
    ]

    private func notification(_ event: EngineEvent, duration: TimeInterval = 754) -> RecordingNotification? {
        RecordingNotifications.notification(for: event, duration: duration)
    }

    private func finished(_ reason: EndReason) -> RecordingNotification? {
        notification(.finished(url: Self.url, reason: reason, droppedFrames: 0))
    }

    // MARK: - Manual stop

    @Test func manualStopNamesTheFileAndItsLength() {
        let n = notification(.finished(url: Self.url, reason: .userStopped, droppedFrames: 0))
        #expect(n?.title == "Recording saved · 00:12:34")
        #expect(n?.body == "Recording 2026-07-15 at 15.24.56.mov")
        #expect(n?.fileURL == Self.url)
    }

    // MARK: - Fail-stops (ADR-007: a success with a cause)

    @Test(arguments: failStops)
    func aFailStopIsStillSaved(reason: EndReason) {
        // The title must NOT differ from a manual stop. A fail-stop produced a playable file; a
        // scarier headline would tell the user they lost something they didn't.
        let n = finished(reason)
        #expect(n?.title == "Recording saved · 00:12:34")
        #expect(n?.body.hasSuffix("File is playable.") == true)
        #expect(n?.fileURL == Self.url)          // click reveals it (docs/06)
    }

    // MARK: - Discard (M6-T12)

    @Test func discardPostsNoNotification() {
        // The confirmation alert was the acknowledgement; a "discarded" banner would be noise.
        #expect(notification(.discarded) == nil)
    }

    @Test(arguments: failStops)
    func everyFailStopNamesItsOwnCause(reason: EndReason) {
        #expect(finished(reason)?.body.hasPrefix("Ended: ") == true)
    }

    @Test func causesAreDistinctPerReason() {
        // A shared phrase would make the notification useless for the thing it exists to do.
        let bodies = Self.failStops.compactMap { finished($0)?.body }
        #expect(Set(bodies).count == Self.failStops.count)
    }

    @Test func appQuitNamesTheCausePlainly() {
        // M7-T1: app-scoped capture ends when its app quits — approved copy (plan review).
        #expect(finished(.appQuit)?.body == "Ended: the recorded app quit. File is playable.")
    }

    @Test func anUnclassifiedStreamErrorSaysWhatHappenedNotWhatSCKSaid() {
        // The raw string ("The stream stopped with error -3818") is the API-speak docs/06 bans.
        let n = finished(.streamError("The stream stopped with error -3818"))
        #expect(n?.body == "Ended: screen capture stopped unexpectedly. File is playable.")
        #expect(n?.body.contains("-3818") == false)
    }

    // MARK: - The two events that aren't endings

    @Test func losingTheMicrophoneLeadsWithStillRecording() {
        // ADR-012: the recording continues. The question this answers is "did my 90-minute
        // capture just die?", so the answer goes in the title, not the body.
        let n = notification(.microphoneLost)
        #expect(n?.title == "Still recording · microphone disconnected")
        #expect(n?.fileURL == nil)               // nothing to reveal yet
    }

    @Test func aRecordingThatNeverStartedSaysSoAndOffersNoFile() {
        let n = notification(.failed(message: "No displays available — the screen may be asleep."))
        #expect(n?.title == "Couldn't start recording")
        #expect(n?.body == "No displays available — the screen may be asleep.")
        #expect(n?.fileURL == nil)
    }

    @Test func aFinalizeFailureIsNotCalledAStartFailure() {
        // `.failed` carries two meanings despite its doc comment: RecordingSession yields it from
        // the `finish()` catch as well, after a full recording. Titling that "Couldn't start
        // recording" contradicts its own body and tells someone who just lost 90 minutes that
        // nothing had started.
        let n = RecordingNotifications.notification(
            for: .failed(message: "Couldn't finalize the recording: disk full"),
            duration: 5400, hadStarted: true)
        #expect(n?.title == "Couldn't save the recording")
        #expect(n?.body == "Couldn't finalize the recording: disk full")
    }

    @Test func theTwoFailuresAreToldApartOnlyByHadStarted() {
        let message = "the same message"
        let start = RecordingNotifications.notification(
            for: .failed(message: message), duration: 0, hadStarted: false)
        let finalize = RecordingNotifications.notification(
            for: .failed(message: message), duration: 90, hadStarted: true)
        #expect(start?.title != finalize?.title)
    }

    // MARK: - Recording started without a microphone (M9-T1)

    @Test func aSpecificMicThatIsAwayIsAnnouncedAtStart() {
        // The gap the mid-recording loss already notifies for, closed at start: outcome first
        // (it IS recording), the cause named, nothing to reveal.
        let n = RecordingNotifications.recordingStart(
            microphonePreference: .device(id: "uid"), resolvedMicName: nil)
        #expect(n?.title == "Recording started · no microphone")
        #expect(n?.body == "The selected microphone isn't connected — recording screen only.")
        #expect(n?.fileURL == nil)
    }

    @Test func automaticWithNothingConnectedSaysNoneIsConnected() {
        let n = RecordingNotifications.recordingStart(
            microphonePreference: .automatic, resolvedMicName: nil)
        #expect(n?.title == "Recording started · no microphone")
        #expect(n?.body == "No microphone is connected — recording screen only.")
    }

    @Test func choosingNoneIsSilent() {
        // A deliberate no-mic is not a miss.
        #expect(RecordingNotifications.recordingStart(
            microphonePreference: .none, resolvedMicName: nil) == nil)
    }

    @Test func aResolvedMicrophoneSaysNothingAtStart() {
        #expect(RecordingNotifications.recordingStart(
            microphonePreference: .device(id: "uid"), resolvedMicName: "AirPods Pro") == nil)
        #expect(RecordingNotifications.recordingStart(
            microphonePreference: .automatic, resolvedMicName: "MacBook Pro Microphone") == nil)
    }

    // MARK: - M6-T3: every failure message says what happened AND what to do

    @Test func diskAlmostFullNamesTheRemedy() {
        let n = RecordingNotifications.notification(
            for: .finished(url: Self.url, reason: .diskAlmostFull, droppedFrames: 0), duration: 4)
        #expect(n?.body.contains("free up space") == true)
        #expect(n?.body.contains("playable") == true)
    }

    @Test func replayFailureCopyIsActionable() {
        #expect(RecordingNotifications.replaySaveFailed().body.contains("writable"))
        #expect(RecordingNotifications.replayStopped().body.contains("Re-arm"))
    }

    // MARK: - Silence

    @Test(arguments: [
        EngineEvent.started, .paused, .resumed, .fileProgress(seconds: 5, bytes: 1),
        .stopped(.userStopped),
    ])
    func nothingElseInterruptsTheUser(event: EngineEvent) {
        // A notification per pause would be noise; `stopped` is the writer-less path the app
        // never sees anyway.
        #expect(notification(event) == nil)
    }

    // MARK: - docs/06's copy rules

    @Test func neverTheWordErrorForAFailStop() {
        // docs/06 states this outright: a fail-stop is not an error, and calling it one tells the
        // user to worry about a file that is fine.
        for reason in Self.failStops {
            let n = finished(reason)
            #expect(n?.title.localizedCaseInsensitiveContains("error") == false)
            #expect(n?.body.localizedCaseInsensitiveContains("error") == false)
        }
    }

    @MainActor
    @Test func aStartThatFailsBeforeAnySessionStillNotifies() {
        // These two paths produce no session and so no event stream. Setting `lastFailure` and
        // returning left Start looking unchanged and the user believing they were recording —
        // exactly the silence ADR-007 forbids.
        let state = AppState(defaults: UserDefaults(suiteName: "notify-\(UUID().uuidString)")!)
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }

        state.apply(.failed(message: "Couldn't create a recording in \"Movies\"."))

        #expect(posted.count == 1)
        #expect(posted.first?.title == "Couldn't start recording")
    }

    @Test func everyNotificationLeadsWithTheOutcome() {
        // "outcome first, cause second". Each title says what happened; no title opens with a
        // cause or an apology.
        var titles = Self.failStops.compactMap { finished($0)?.title }
        titles.append(notification(.microphoneLost)?.title ?? "")
        titles.append(notification(.failed(message: "x"))?.title ?? "")
        for title in titles {
            #expect(title.hasPrefix("Recording saved")
                    || title.hasPrefix("Still recording")
                    || title.hasPrefix("Couldn't start"))
        }
    }

    @Test func aFileIsOfferedExactlyWhenOneExists() {
        // The invariant behind "click always reveals the file": every notification about a
        // finished file carries it, and the two that aren't about a file carry nothing.
        for reason in Self.failStops + [.userStopped] {
            #expect(finished(reason)?.fileURL != nil)
        }
        #expect(notification(.microphoneLost)?.fileURL == nil)
        #expect(notification(.failed(message: "x"))?.fileURL == nil)
    }

    @Test func aDurationThatNeverStartedReadsAsZeroNotGarbage() {
        // `recordedDuration` is NaN before the first frame (02 §10); the caller sanitizes, but a
        // zero-length finish is still reachable.
        let n = notification(.finished(url: Self.url, reason: .userStopped, droppedFrames: 0),
                             duration: 0)
        #expect(n?.title == "Recording saved · 00:00:00")
    }
}
