import Foundation
import Testing
import UploadCore

@testable import AppCore

/// A failed upload kept in the menu and tried again (M40-T6): what is remembered, what `Try
/// Again` sends, and what the notices say about it.
@MainActor
@Suite struct UploadRetryTests {

    private let credentials = GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret")
    private let metadata = VideoMetadata(title: "My clip", description: "About it", privacy: .unlisted)
    private let session = UploadSession(
        url: URL(string: "https://upload.example/session-1")!, fileSize: 1000, contentType: "video/mp4")
    private let video = UploadedVideo(
        id: "abc123XYZ_-", title: "My clip", privacyStatus: "unlisted", uploadStatus: "uploaded",
        channelTitle: "My channel")

    private func token() -> GoogleToken {
        GoogleToken(
            accessToken: "at", accessTokenExpiry: Date().addingTimeInterval(3000), refreshToken: "rt")
    }

    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-retry-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 1000).write(to: url)
        return url
    }

    private func makeModel() -> (model: UploadModel, posted: Posted) {
        let model = UploadModel(credentials: credentials, store: InMemoryTokenStore(token()))
        let posted = Posted()
        model.notify = { posted.append($0) }
        return (model, posted)
    }

    private func drain(_ model: UploadModel) async {
        while model.uploadInProgress != nil || model.queuedUploadCount > 0 {
            await model.uploadTask?.value
        }
    }

    /// What the uploader was handed on each attempt.
    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [UploadSession?] = []

        func record(_ continuing: UploadSession?) -> Int {
            lock.withLock {
                seen.append(continuing)
                return seen.count
            }
        }
        var continuing: [UploadSession?] { lock.withLock { seen } }
    }

    /// Fails once after YouTube opened the upload, then lands.
    private func failOnceAfterOpening(
        _ model: UploadModel, attempts: Attempts, first: any Error = UploadGaveUp(underlying: URLError(.networkConnectionLost))
    ) {
        model.uploadFunction = { [session, video] _, _, pass, progress in
            guard attempts.record(pass.continuing) == 1 else { return video }
            pass.opened(session)
            progress(400)
            throw first
        }
    }

    // MARK: - What is kept

    @Test func aFailedUploadIsKeptWithWhatItWasAndWhyItStopped() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        #expect(model.failedUpload == nil)
        failOnceAfterOpening(model, attempts: Attempts())

        model.upload(file, metadata: metadata)
        await drain(model)

        let failed = try #require(model.failedUpload)
        #expect(failed.title == "My clip")
        #expect(failed.file == file)
        #expect(failed.failure == .connectionLost)
        #expect(failed.leavesEntry)
        #expect(failed.canTryAgain)
        #expect(failed.menuTitle == "Couldn't upload · My clip")
        // The entry is not something to delete when Try Again would finish it.
        #expect(
            posted.all.first?.body
                == "The connection dropped and didn't come back in 5 minutes. Try Again in the menu continues where it stopped. The clip is saved as \(file.lastPathComponent).")
    }

    // MARK: - Trying again

    /// The point of the task: the same upload is picked up, so the entry it left becomes the
    /// video and no second one is made — with the title, description and visibility as typed.
    @Test func tryingAgainContinuesTheSameUploadWithWhatTheSheetHeld() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let attempts = Attempts()
        let sent = Calls()
        model.uploadFunction = { [session, video] file, metadata, pass, _ in
            sent.record(file: file, metadata: metadata, accessToken: pass.token)
            guard attempts.record(pass.continuing) == 1 else { return video }
            pass.opened(session)
            throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
        }
        model.upload(file, metadata: metadata)
        await drain(model)

        model.tryAgain()
        #expect(model.failedUpload == nil)            // the row goes as the retry starts
        #expect(model.uploadInProgress == "My clip")
        await drain(model)

        #expect(attempts.continuing == [nil, session])
        #expect(sent.all.map(\.metadata) == [metadata, metadata])
        #expect(sent.all.map(\.file) == [file, file])
        #expect(posted.all.map(\.title) == ["Couldn't upload to YouTube", "Uploaded to YouTube"])
        #expect(model.lastUpload?.videoID == "abc123XYZ_-")
        #expect(model.failedUpload == nil)
    }

    /// Refused before anything was opened — the daily limit — there is nothing to continue.
    @Test func tryingAgainStartsAFreshUploadWhenNothingWasOpened() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let attempts = Attempts()
        model.uploadFunction = { [video] _, _, pass, _ in
            guard attempts.record(pass.continuing) == 1 else { return video }
            throw YouTubeError.uploadLimitExceeded
        }
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(model.failedUpload?.leavesEntry == false)

        model.tryAgain()
        await drain(model)

        #expect(attempts.continuing == [nil, nil])
        #expect(posted.all.map(\.title) == ["Couldn't upload to YouTube", "Uploaded to YouTube"])
    }

    @Test func aRetryThatFailsBringsTheRowBackWithTheNewReason() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel()
        let attempts = Attempts()
        model.uploadFunction = { [session] _, _, pass, _ in
            if attempts.record(pass.continuing) == 1 {
                pass.opened(session)
                throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
            }
            throw YouTubeError.uploadLimitExceeded
        }
        model.upload(file, metadata: metadata)
        await drain(model)
        model.tryAgain()
        await drain(model)

        #expect(model.failedUpload?.failure == .channelLimitReached)
        // Still the same unfinished upload underneath: the next try continues it again.
        model.tryAgain()
        await drain(model)
        #expect(attempts.continuing == [nil, session, session])
    }

    /// Trying again could only fail the same way: the row explains, and offers nothing to press.
    @Test func aFailureThatWouldOnlyRepeatCannotBeTriedAgain() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString).mp4")
        let (model, posted) = makeModel()
        let attempts = Attempts()
        model.uploadFunction = { [video] _, _, pass, _ in
            _ = attempts.record(pass.continuing)
            return video
        }
        model.upload(missing, metadata: metadata)
        await drain(model)

        let failed = try #require(model.failedUpload)
        #expect(failed.failure == .clipMissing)
        #expect(!failed.canTryAgain)
        model.tryAgain()
        await drain(model)
        #expect(attempts.continuing.isEmpty)
        #expect(model.failedUpload == failed)
        #expect(posted.all.count == 1)
    }

    /// A session has a finite life. The uploader starts over when it is gone, and the notice
    /// says the entry the first attempt left may still be there.
    @Test func aRetryThatHadToStartOverSaysTheEarlierEntryMayRemain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let attempts = Attempts()
        model.uploadFunction = { [session, video] _, _, pass, _ in
            if attempts.record(pass.continuing) == 1 {
                pass.opened(session)
                throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
            }
            pass.startedOver()
            return video
        }
        model.upload(file, metadata: metadata)
        await drain(model)
        model.tryAgain()
        await drain(model)

        #expect(
            posted.all.last?.body.hasSuffix(
                "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio.") == true)
    }

    /// A retry continues an upload YouTube already holds an entry for. Stopping it leaves that
    /// entry however little the retry itself got done — so it says so, even before the uploader
    /// has reported anything.
    @Test func stoppingARetryStillSaysWhatIsLeftOnYouTube() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let attempts = Attempts()
        let retrying = Gate()
        model.uploadFunction = { [session, video] _, _, pass, _ in
            if attempts.record(pass.continuing) == 1 {
                pass.opened(session)
                throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
            }
            retrying.open()                           // and reports nothing at all
            try await Task.sleep(for: .seconds(60))
            return video
        }
        model.upload(file, metadata: metadata)
        await drain(model)

        model.tryAgain()
        await retrying.reached()
        #expect(model.stoppedUploadLeavesEntry)
        model.cancelUpload(try #require(model.currentUploadToken))
        await drain(model)

        #expect(posted.all.map(\.title) == ["Couldn't upload to YouTube", "Upload to YouTube stopped"])
    }

    // MARK: - The clipboard, the account and the clip

    /// The press is the new "confirm": what was copied between the failure and the retry is
    /// not a change made while it uploaded.
    @Test func theClipboardRuleCountsFromTheTryAgainPress() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let clipboard = Box<Int>()
        clipboard.value = 3
        let copied = Box<String>()
        model.clipboardChangeCount = { clipboard.value ?? 0 }
        model.copyToClipboard = { copied.value = $0 }
        failOnceAfterOpening(model, attempts: Attempts())

        model.upload(file, metadata: metadata)
        await drain(model)
        clipboard.value = 9                       // something else was copied in between
        model.tryAgain()
        await drain(model)

        #expect(copied.value == "https://youtu.be/abc123XYZ_-")
        #expect(posted.all.last?.title == "Uploaded to YouTube · link copied")
    }

    /// A session belongs to the account that opened it. After a sign-in ends the next one may
    /// be another's, so the retry starts from nothing — and the notice keeps the entry sentence.
    @Test func aSignInThatEndedLeavesARetryThatStartsFromTheBeginning() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token())
        let model = UploadModel(credentials: credentials, store: store)
        let posted = Posted()
        model.notify = { posted.append($0) }
        let attempts = Attempts()
        failOnceAfterOpening(model, attempts: attempts, first: GoogleSignInError.signInExpired)

        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(model.account == .disconnected)
        #expect(
            posted.all.first?.body
                == "YouTube needs reconnecting: the sign-in has ended. Connect again in Settings. Try Again is in the menu. The clip is saved as \(file.lastPathComponent). YouTube keeps an unfinished entry named “My clip”; delete it in YouTube Studio.")

        try store.save(token())                   // connected again, perhaps as someone else
        model.signIn = { [token = token()] _, _ in token }
        await model.connectAndWait()
        model.tryAgain()
        await drain(model)
        #expect(attempts.continuing == [nil, nil])
    }

    /// The same when the disconnect comes while the upload is still running: its session was
    /// opened under the account that has gone. Continuing it under the next one could put the
    /// video on a channel the user disconnected from.
    @Test func anUploadRunningAtADisconnectIsNotContinuedUnderTheNextAccount() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        model.revoke = { _ in }
        let attempts = Attempts()
        let opened = Gate()
        let fail = Gate()
        model.uploadFunction = { [session, video] _, _, pass, _ in
            guard attempts.record(pass.continuing) == 1 else { return video }
            pass.opened(session)
            opened.open()
            await fail.wait()
            throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
        }
        model.upload(file, metadata: metadata)
        await opened.reached()

        await model.disconnect()                       // account A goes while the upload runs
        fail.open()
        await drain(model)
        // Nothing here can finish that entry any more, so the notice says to delete it.
        #expect(
            posted.all.first?.body.hasSuffix(
                "Try Again is in the menu. The clip is saved as \(file.lastPathComponent). YouTube keeps an unfinished entry named “My clip”; delete it in YouTube Studio.") == true)

        model.signIn = { [token = token()] _, _ in token }
        await model.connectAndWait()                   // account B, for all the model knows
        model.tryAgain()
        await drain(model)
        #expect(attempts.continuing == [nil, nil])
        #expect(
            posted.all.last?.body.hasSuffix(
                "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio.") == true)
    }

    /// The notice promised "continues where it stopped" and so did not say to delete the entry.
    /// A sign-out afterwards breaks that promise; the upload that finally lands has to say what
    /// was left behind.
    @Test func aRetryThatCanNoLongerContinueSaysWhatTheFirstAttemptLeft() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        model.revoke = { _ in }
        let attempts = Attempts()
        failOnceAfterOpening(model, attempts: attempts)
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(posted.all.first?.body.contains("continues where it stopped") == true)
        #expect(posted.all.first?.body.contains("delete it") == false)

        await model.disconnect()
        model.signIn = { [token = token()] _, _ in token }
        await model.connectAndWait()
        model.tryAgain()
        await drain(model)

        #expect(attempts.continuing == [nil, nil])
        #expect(
            posted.all.last?.body.hasSuffix(
                "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio.") == true)
    }

    /// A retry that had to start over and then failed before opening anything: YouTube holds
    /// nothing for *that* attempt, and the earlier entry is still owed a mention when it lands.
    @Test func startingOverIsRememberedThroughAFailureThatOpenedNothing() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let attempts = Attempts()
        model.uploadFunction = { [session, video] _, _, pass, _ in
            switch attempts.record(pass.continuing) {
            case 1:
                pass.opened(session)
                throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
            case 2:
                pass.startedOver()                    // the session was gone
                throw YouTubeError.uploadLimitExceeded // and the new one never opened
            default:
                return video
            }
        }
        model.upload(file, metadata: metadata)
        await drain(model)
        model.tryAgain()
        await drain(model)

        // This attempt left nothing: its notice does not claim an entry named after it, and
        // says what the first one may have left — nothing else would, if it is never retried.
        #expect(posted.all.last?.body.contains("YouTube keeps an unfinished entry named") == false)
        #expect(
            posted.all.last?.body.hasSuffix(
                "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio.") == true)
        // But the first one's may still be there, so the row still offers Studio.
        #expect(model.failedUpload?.leavesEntry == true)

        model.tryAgain()
        await drain(model)
        #expect(attempts.continuing == [nil, session, nil])
        #expect(
            posted.all.last?.body.hasSuffix(
                "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio.") == true)
    }

    /// The clip went up another way. Its failed row would now only offer to publish it twice.
    @Test func theSameClipLandingAnotherWayClearsItsFailedRow() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let other = try makeFile()
        defer { try? FileManager.default.removeItem(at: other) }
        let (model, posted) = makeModel()
        failOnceAfterOpening(model, attempts: Attempts())
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(model.failedUpload != nil)

        // Another clip landing changes nothing.
        model.upload(other, metadata: VideoMetadata(title: "Other", privacy: .unlisted))
        await drain(model)
        #expect(model.failedUpload != nil)
        #expect(posted.all.last?.body.contains("earlier unfinished entry") == false)

        // The same clip, uploaded afresh through the sheet.
        model.upload(file, metadata: VideoMetadata(title: "Again", privacy: .unlisted))
        await drain(model)
        #expect(model.failedUpload == nil)
        // The first attempt's entry is still on YouTube, and nothing will finish it now.
        #expect(
            posted.all.last?.body.hasSuffix(
                "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio.") == true)
        model.tryAgain()
        #expect(model.uploadInProgress == nil)
    }

    @Test func disconnectingForgetsTheSessionOfAFailedUploadButNotTheUpload() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel()
        model.revoke = { _ in }
        let attempts = Attempts()
        failOnceAfterOpening(model, attempts: attempts)
        model.upload(file, metadata: metadata)
        await drain(model)

        await model.disconnect()
        #expect(model.failedUpload != nil)
        model.signIn = { [token = token()] _, _ in token }
        await model.connectAndWait()
        model.tryAgain()
        await drain(model)
        #expect(attempts.continuing == [nil, nil])
    }

    @Test func renamingTheClipTakesItsFailedUploadWithIt() async throws {
        let file = try makeFile()
        let renamed = file.deletingLastPathComponent()
            .appendingPathComponent("renamed-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: renamed)
        }
        let (model, _) = makeModel()
        let sent = Calls()
        let attempts = Attempts()
        model.uploadFunction = { [video] file, metadata, pass, _ in
            sent.record(file: file, metadata: metadata, accessToken: pass.token)
            guard attempts.record(pass.continuing) == 1 else { return video }
            throw YouTubeError.uploadLimitExceeded
        }
        model.upload(file, metadata: metadata)
        await drain(model)

        try FileManager.default.moveItem(at: file, to: renamed)
        model.fileRenamed(from: file, to: renamed)
        #expect(model.failedUpload?.file == renamed)
        model.tryAgain()
        await drain(model)
        #expect(sent.all.map(\.file) == [file, renamed])
    }

    // MARK: - How long the row stays

    @Test func theRowGoesWhenDismissedOrReplacedOrADayOld() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel()
        model.uploadFunction = { _, _, _, _ in throw YouTubeError.uploadLimitExceeded }
        model.upload(file, metadata: metadata)
        await drain(model)
        let failedAt = try #require(model.failedUpload?.date)

        // Unfinished business rather than news: it outlasts a receipt's hour.
        model.prepareForMenu(now: failedAt.addingTimeInterval(23 * 3600))
        #expect(model.failedUpload != nil)
        model.prepareForMenu(now: failedAt.addingTimeInterval(25 * 3600))
        #expect(model.failedUpload == nil)

        model.upload(file, metadata: metadata)
        await drain(model)
        model.uploadFunction = { _, _, _, _ in throw YouTubeError.noChannel }
        model.upload(file, metadata: VideoMetadata(title: "Newer", privacy: .unlisted))
        await drain(model)
        #expect(model.failedUpload?.title == "Newer")          // only the latest is kept
        #expect(model.failedUpload?.failure == .noChannel)

        model.dismissFailedUpload()
        #expect(model.failedUpload == nil)
        model.tryAgain()                                       // nothing to try
        #expect(model.uploadInProgress == nil)
    }

    // MARK: - The words

    @Test func theNoticeSaysWhatTryAgainWouldDo() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        func body(_ retry: UploadRetry, leavesEntry: Bool) -> String {
            RecordingNotifications.uploadFailed(
                reason: "Why.", title: "My clip", file: file, clipExists: true,
                leavesEntry: leavesEntry, retry: retry
            ).body
        }
        let entry = "YouTube keeps an unfinished entry named “My clip”; delete it in YouTube Studio."
        #expect(body(.none, leavesEntry: true) == "Why. The clip is saved as Clip trimmed.mp4. \(entry)")
        // Finishing the upload is what removes the entry, so it is not something to delete.
        #expect(
            body(.continues, leavesEntry: true)
                == "Why. Try Again in the menu continues where it stopped. The clip is saved as Clip trimmed.mp4.")
        #expect(
            body(.startsFresh, leavesEntry: true)
                == "Why. Try Again is in the menu. The clip is saved as Clip trimmed.mp4. \(entry)")
        #expect(body(.startsFresh, leavesEntry: false) == "Why. Try Again is in the menu. The clip is saved as Clip trimmed.mp4.")
    }

    /// An entry an earlier attempt left is named when this attempt holds none of its own: with
    /// two unfinished entries of one name, "delete the earlier one" could cost the live one.
    @Test func theNoticeNamesAnEarlierEntryOnlyWhenItCannotBeMistaken() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        func body(_ retry: UploadRetry, leavesEntry: Bool) -> String {
            RecordingNotifications.uploadFailed(
                reason: "Why.", title: "My clip", file: file, clipExists: true,
                leavesEntry: leavesEntry, retry: retry, earlierEntryMayRemain: true
            ).body
        }
        let saved = "The clip is saved as Clip trimmed.mp4."
        let earlier = "An earlier unfinished entry may still be on your channel; delete it in YouTube Studio."
        let own = "YouTube keeps an unfinished entry named “My clip”; delete it in YouTube Studio."
        #expect(body(.startsFresh, leavesEntry: false) == "Why. Try Again is in the menu. \(saved) \(earlier)")
        #expect(body(.none, leavesEntry: false) == "Why. \(saved) \(earlier)")
        // Its own entry is the one named: Studio shows both, under the same name.
        #expect(body(.startsFresh, leavesEntry: true) == "Why. Try Again is in the menu. \(saved) \(own)")
        // And nothing is to be deleted while Try Again can still finish the live one.
        #expect(
            body(.continues, leavesEntry: true)
                == "Why. Try Again in the menu continues where it stopped. \(saved)")
    }

    @Test func theRowsFirstLineIsTheReasonsFirstSentence() {
        func line(_ failure: UploadFailure, clipExists: Bool = true) -> String {
            UploadCopy.menuReason(
                FailedUpload(
                    title: "T", file: URL(fileURLWithPath: "/tmp/x.mp4"), failure: failure,
                    date: Date(), leavesEntry: false),
                clipExists: clipExists)
        }
        #expect(line(.connectionLost) == "The connection dropped and didn't come back in 5 minutes.")
        #expect(line(.channelLimitReached) == "Your channel has reached YouTube's upload limit for today.")
        #expect(line(.signInEnded) == "YouTube needs reconnecting.")
        #expect(line(.projectNotSetUp) == "This build can't upload.")
        #expect(line(.noChannel) == "This Google account has no YouTube channel.")
        #expect(line(.clipMissing, clipExists: false) == "The clip was moved or deleted before it could be sent.")
        #expect(line(.clipMissing, clipExists: true) == "The clip couldn't be read.")
    }

    @Test func aLongTitleIsCutInTheFailedRowToo() {
        let failed = FailedUpload(
            title: String(repeating: "a", count: 100), file: URL(fileURLWithPath: "/tmp/x.mp4"),
            failure: .other, date: Date(), leavesEntry: false)
        #expect(failed.menuTitle == "Couldn't upload · \(String(repeating: "a", count: 39))…")
    }
}
