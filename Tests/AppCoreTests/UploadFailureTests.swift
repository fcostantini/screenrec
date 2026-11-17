import Foundation
import Testing
import UploadCore

@testable import AppCore

/// What the app does and says when an upload does not land (M40-T5): the notice's three parts,
/// a sign-in renewed or found dead in the middle of a transfer, and the waiting state.
@MainActor
@Suite struct UploadFailureTests {

    private let credentials = GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret")
    private let metadata = VideoMetadata(title: "My clip", description: "", privacy: .unlisted)
    private let entry = "YouTube keeps an unfinished entry named “My clip”; delete it in YouTube Studio."

    private func token(_ access: String = "at") -> GoogleToken {
        GoogleToken(
            accessToken: access, accessTokenExpiry: Date().addingTimeInterval(3000), refreshToken: "rt")
    }

    private let video = UploadedVideo(
        id: "abc123XYZ_-", title: "My clip", privacyStatus: "unlisted", uploadStatus: "uploaded",
        channelTitle: "My channel")

    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-failure-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 1000).write(to: url)
        return url
    }

    private func makeModel(
        store: any TokenStore
    ) -> (model: UploadModel, posted: Posted) {
        let model = UploadModel(credentials: credentials, store: store)
        let posted = Posted()
        model.notify = { posted.append($0) }
        return (model, posted)
    }

    private func drain(_ model: UploadModel) async {
        while model.uploadInProgress != nil || model.queuedUploadCount > 0 {
            await model.uploadTask?.value
        }
    }

    // MARK: - What the notice ends with

    /// YouTube makes the video's entry when the upload opens. A failure after that leaves one
    /// behind, and the app cannot delete it — so the notice says so, as a stopped upload's does.
    @Test func aFailureAfterYouTubeOpenedTheUploadSaysWhatItLeaves() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        model.uploadFunction = { _, _, _, progress in
            progress(0)   // the session is open
            throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
        }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(
            posted.all.first?.body
                == "The connection dropped and didn't come back in 5 minutes. The clip is saved as \(file.lastPathComponent). \(entry)")
        #expect(model.account == .connected(expires: nil))
    }

    /// The daily limit is refused before anything is opened: there is nothing on YouTube to mention.
    @Test func aFailureBeforeYouTubeOpenedAnythingLeavesNothingToMention() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        model.uploadFunction = { _, _, _, _ in throw YouTubeError.uploadLimitExceeded }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(
            posted.all.first?.body
                == "Your channel has reached YouTube's upload limit for today. YouTube lifts it within a day. The clip is saved as \(file.lastPathComponent).")
    }

    /// An expired session is YouTube letting go of the entry, not keeping it.
    @Test func aSessionYouTubeGaveUpOnIsNotSaidToLeaveAnEntry() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        model.uploadFunction = { _, _, _, progress in
            progress(0)
            throw YouTubeError.sessionExpired
        }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(
            posted.all.first?.body
                == "YouTube gave up on the unfinished upload. Upload the clip again. The clip is saved as \(file.lastPathComponent).")
    }

    /// "The clip is saved as…" is untrue when the clip going missing is the failure.
    @Test func aClipThatHasGoneIsNotSaidToBeSaved() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString).mp4")
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        let calls = Calls()
        model.uploadFunction = { [video] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        model.upload(missing, metadata: metadata)
        await drain(model)

        #expect(calls.all.isEmpty)
        #expect(posted.all.first?.body == "The clip was moved or deleted before it could be sent.")
        #expect(posted.all.first?.fileURL == nil)
    }

    // MARK: - The sign-in, in the middle of a transfer

    /// The token lasts an hour and an upload can last longer. The uploader asks for a renewed
    /// one, and what it gets is saved, so the next upload starts from it.
    @Test func aTokenThatLapsesMidUploadIsRenewedAndKept() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token("stale"))
        let (model, posted) = makeModel(store: store)
        model.refresh = { [fresh = token("fresh")] _, _ in fresh }
        let used = Box<String>()
        model.uploadFunction = { [video] _, _, pass, _ in
            used.value = "\(pass.token) then \(try await pass.renew())"
            return video
        }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(used.value == "stale then fresh")
        #expect(store.load()?.accessToken == "fresh")
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
        #expect(model.account == .connected(expires: nil))
    }

    /// Google refusing the renewal is how a dead sign-in is found: removed in the Google account,
    /// or dropped by Google. The account stops claiming to be connected, wherever it is shown.
    @Test func aRenewalGoogleRefusesEndsTheConnection() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token())
        let (model, posted) = makeModel(store: store)
        model.refresh = { _, _ in throw GoogleSignInError.signInExpired }
        model.uploadFunction = { [video] _, _, pass, progress in
            progress(0)
            _ = try await pass.renew()
            return video
        }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(model.account == .disconnected)
        #expect(store.load() == nil)
        #expect(model.lastFailure == "The last sign-in has ended. Connect again.")
        #expect(
            posted.all.first?.body
                == "YouTube needs reconnecting: the sign-in has ended. Connect again in Settings. The clip is saved as \(file.lastPathComponent). \(entry)")
    }

    /// A token Google has just renewed and YouTube still turns down is not a dead sign-in: the
    /// grant stands at Google, and deleting the local copy would leave it there with nothing
    /// here able to end it — what Disconnect is careful never to do. So the account is kept.
    @Test func aSignInYouTubeRefusesAlthoughGoogleRenewedItIsKept() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token())
        let (model, posted) = makeModel(store: store)
        model.uploadFunction = { _, _, _, _ in throw YouTubeError.notAuthorized }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(model.account == .connected(expires: nil))
        #expect(store.load() != nil)
        #expect(model.lastFailure == nil)
        #expect(
            posted.all.first?.body
                == "YouTube didn't accept the sign-in. Try again; if it keeps happening, disconnect and connect again in Settings. The clip is saved as \(file.lastPathComponent).")
    }

    /// An empty file is still there: it is not "moved or deleted", and it is still "saved".
    @Test func aClipThatIsThereButCannotBeReadIsNotSaidToHaveGone() async throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).mp4")
        try Data().write(to: empty)
        defer { try? FileManager.default.removeItem(at: empty) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))

        model.upload(empty, metadata: metadata)
        await drain(model)

        #expect(
            posted.all.first?.body
                == "The clip couldn't be read. The clip is saved as \(empty.lastPathComponent).")
        #expect(posted.all.first?.fileURL == empty)
    }

    /// A failure that is not about the sign-in leaves it alone.
    @Test func anyOtherFailureKeepsTheAccountConnected() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token())
        let (model, _) = makeModel(store: store)
        for error: any Error in [YouTubeError.quotaExceeded, YouTubeError.noChannel, URLError(.timedOut)] {
            model.uploadFunction = { _, _, _, _ in throw error }
            model.upload(file, metadata: metadata)
            await drain(model)
            #expect(model.account == .connected(expires: nil))
            #expect(store.load() != nil)
        }
    }

    // MARK: - Waiting to be picked up

    @Test func theModelSaysWhenTheTransferIsWaitingAndWhenItMovesAgain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel(store: InMemoryTokenStore(token()))
        let dropped = Gate()
        let resume = Gate()
        let resumed = Gate()
        let finish = Gate()
        model.uploadFunction = { [video] _, _, pass, _ in
            pass.waiting(true)
            dropped.open()
            await resume.wait()
            pass.waiting(false)
            resumed.open()
            await finish.wait()
            return video
        }
        #expect(!model.uploadIsWaiting)

        model.upload(file, metadata: metadata)
        await dropped.reached()
        for _ in 0..<2000 where !model.uploadIsWaiting { await Task.yield() }
        #expect(model.uploadIsWaiting)

        resume.open()
        await resumed.reached()
        for _ in 0..<2000 where model.uploadIsWaiting { await Task.yield() }
        #expect(!model.uploadIsWaiting)

        finish.open()
        await drain(model)
        #expect(!model.uploadIsWaiting)
    }

    /// An upload that fails while waiting must not leave the next one marked as waiting.
    @Test func theWaitingStateEndsWithTheUploadItBelongedTo() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel(store: InMemoryTokenStore(token()))
        let waiting = Gate()
        let giveUp = Gate()
        model.uploadFunction = { _, _, pass, _ in
            pass.waiting(true)
            waiting.open()
            await giveUp.wait()
            throw URLError(.networkConnectionLost)
        }

        model.upload(file, metadata: metadata)
        await waiting.reached()
        for _ in 0..<2000 where !model.uploadIsWaiting { await Task.yield() }
        try #require(model.uploadIsWaiting)

        giveUp.open()
        await drain(model)
        #expect(!model.uploadIsWaiting)
    }

    /// The uploader reports from its own queue and each report hops to the main actor on its
    /// own, so two can cross. What is shown has to be what was said last.
    @Test func theLastThingSaidAboutWaitingIsWhatIsShown() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel(store: InMemoryTokenStore(token()))
        let said = Gate()
        let finish = Gate()
        model.uploadFunction = { [video] _, _, pass, _ in
            for _ in 0..<50 {
                pass.waiting(false)
                pass.waiting(true)
            }
            said.open()
            await finish.wait()
            return video
        }

        model.upload(file, metadata: metadata)
        await said.reached()
        for _ in 0..<2000 { await Task.yield() }
        #expect(model.uploadIsWaiting)

        finish.open()
        await drain(model)
    }

    /// `send` awaits a refresh before it starts the transfer, and the upload can have been
    /// abandoned and replaced by then. The one that was stopped must start nothing, and must not
    /// speak for its successor.
    @Test func anUploadStoppedWhileItPreparedStartsNothingAfterwards() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(
            GoogleToken(
                accessToken: "at", accessTokenExpiry: Date().addingTimeInterval(30), refreshToken: "rt"))
        let (model, posted) = makeModel(store: store)
        let refreshing = Gate()
        let refreshed = Gate()
        let refreshes = Calls()
        model.refresh = { [fresh = token("fresh")] _, _ in
            refreshes.record(file: file, metadata: VideoMetadata(title: "", privacy: .private), accessToken: "")
            if refreshes.all.count == 1 {
                refreshing.open()
                await refreshed.wait()
            }
            return fresh
        }
        let calls = Calls()
        let secondWaiting = Gate()
        let finish = Gate()
        model.uploadFunction = { [video] file, metadata, pass, _ in
            calls.record(file: file, metadata: metadata, accessToken: pass.token)
            pass.waiting(true)
            secondWaiting.open()
            await finish.wait()
            return video
        }

        model.upload(file, metadata: metadata)                 // the first: stuck renewing
        await refreshing.reached()
        model.cancelAllUploads()
        model.upload(file, metadata: VideoMetadata(title: "Second", privacy: .unlisted))
        await secondWaiting.reached()
        for _ in 0..<2000 where !model.uploadIsWaiting { await Task.yield() }
        try #require(model.uploadIsWaiting)

        refreshed.open()                                       // the first one's renewal lands now
        for _ in 0..<500 { await Task.yield() }
        #expect(calls.all.count == 1)                          // it started no transfer
        #expect(model.uploadIsWaiting)                         // and said nothing for the second
        #expect(model.uploadInProgress == "Second")

        finish.open()
        await drain(model)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
    }

    @Test func theRowSaysWhyThePercentageHasStopped() {
        #expect(MenuHeader.uploadNote(waiting: 0, reconnecting: false) == nil)
        #expect(MenuHeader.uploadNote(waiting: 2, reconnecting: false) == "· 2 waiting")
        // Why the number has stopped matters more than what is queued behind it.
        #expect(MenuHeader.uploadNote(waiting: 2, reconnecting: true) == "· waiting for the connection")
        #expect(
            MenuHeader.uploading(fraction: 0.41, note: "· waiting for the connection")
                == "Uploading to YouTube… 41% · waiting for the connection")
        #expect(MenuHeader.uploading(fraction: 0.41, note: nil) == "Uploading to YouTube… 41%")
    }
}
