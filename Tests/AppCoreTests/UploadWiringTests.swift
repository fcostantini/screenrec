import Foundation
import RecorderCore
import Testing
import UploadCore

@testable import AppCore

/// An upload from start to finish with the encoder, the network and the sign-in all injected
/// (M40-T3): what the uploader is handed, in what order, and what the user is told.
@MainActor
@Suite struct UploadWiringTests {

    private let credentials = GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret")
    private let metadata = VideoMetadata(title: "My clip", description: "About it", privacy: .unlisted)

    private func token(expiresIn seconds: TimeInterval = 3000) -> GoogleToken {
        GoogleToken(
            accessToken: "at", accessTokenExpiry: Date().addingTimeInterval(seconds), refreshToken: "rt")
    }

    private func video(_ id: String = "abc123XYZ_-", channel: String? = "My channel") -> UploadedVideo {
        UploadedVideo(
            id: id, title: "My clip", privacyStatus: "unlisted", uploadStatus: "uploaded",
            channelTitle: channel)
    }

    /// A real file: the model reads its size to turn bytes sent into a fraction.
    private func makeFile(bytes: Int = 1000) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-wiring-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func makeModel(
        store: any TokenStore, defaults: UserDefaults? = nil
    ) -> (model: UploadModel, posted: Posted) {
        let model = UploadModel(credentials: credentials, store: store, defaults: defaults)
        let posted = Posted()
        model.notify = { posted.append($0) }
        return (model, posted)
    }

    private func drain(_ model: UploadModel) async {
        while model.uploadInProgress != nil || model.queuedUploadCount > 0 {
            await model.uploadTask?.value
        }
    }

    // MARK: - The upload

    @Test func anUploadSendsTheFileWithWhatTheSheetHeldAndSaysItLanded() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        let calls = Calls()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        model.upload(file, metadata: metadata)
        #expect(model.uploadInProgress == "My clip")
        await drain(model)

        #expect(calls.all.count == 1)
        #expect(calls.all.first?.file == file)
        #expect(calls.all.first?.metadata == metadata)
        #expect(calls.all.first?.accessToken == "at")
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
        #expect(posted.all.first?.link == URL(string: "https://youtu.be/abc123XYZ_-"))
        #expect(posted.all.first?.fileURL == file)
        #expect(model.uploadInProgress == nil)
        #expect(model.uploadProgress == nil)
    }

    @Test func progressIsAFractionOfTheFile() async throws {
        let file = try makeFile(bytes: 1000)
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel(store: InMemoryTokenStore(token()))
        let gate = Gate()
        model.uploadFunction = { [video = video()] _, _, _, progress in
            progress(250)
            await gate.wait()
            return video
        }

        model.upload(file, metadata: metadata)
        for _ in 0..<200 where model.uploadProgress != 0.25 { await Task.yield() }
        #expect(model.uploadProgress == 0.25)
        gate.open()
        await drain(model)
    }

    /// One at a time and in order: two transfers sharing an uplink would both be slower, and the
    /// one bar could only describe one of them.
    @Test func uploadsAskedForTogetherRunInOrder() async throws {
        let first = try makeFile()
        let second = try makeFile()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        let calls = Calls()
        let gate = Gate()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            if calls.all.count == 1 { await gate.wait() }
            return video
        }

        model.upload(first, metadata: metadata)
        model.upload(second, metadata: VideoMetadata(title: "Second", privacy: .private))
        #expect(model.queuedUploadCount == 1)
        for _ in 0..<200 where calls.all.isEmpty { await Task.yield() }
        #expect(calls.all.map(\.file) == [first])

        gate.open()
        await drain(model)
        #expect(calls.all.map(\.file) == [first, second])
        #expect(posted.all.count == 2)
    }

    // MARK: - The sign-in

    /// The token is renewed before the transfer starts rather than discovered dead in the middle
    /// of it, and the renewed one is what is kept.
    @Test func aSignInAboutToLapseIsRefreshedFirstAndSaved() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token(expiresIn: 30))
        let (model, _) = makeModel(store: store)
        var renewed = token()
        renewed.accessToken = "fresh"
        let calls = Calls()
        model.refresh = { [renewed] _, _ in renewed }
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(calls.all.first?.accessToken == "fresh")
        #expect(store.load()?.accessToken == "fresh")
    }

    /// Google no longer honours it: nothing is sent, the account stops claiming to be connected,
    /// and the notice says what to do.
    @Test func aSignInGoogleHasDroppedEndsTheUploadAndTheConnection() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token(expiresIn: -10))
        let (model, posted) = makeModel(store: store)
        let calls = Calls()
        model.refresh = { _, _ in throw GoogleSignInError.signInExpired }
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(calls.all.isEmpty)
        #expect(model.account == .disconnected)
        #expect(store.load() == nil)
        #expect(posted.all.map(\.title) == ["Couldn't upload to YouTube"])
        #expect(
            posted.all.first?.body.hasPrefix(
                "YouTube needs reconnecting: the sign-in has ended. Connect again in Settings.") == true)
    }

    /// The refresh is a round trip to Google, long enough for a disconnect to finish inside it.
    @Test func aDisconnectDuringTheRefreshIsNotUndoneByIt() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token(expiresIn: 30))
        let (model, posted) = makeModel(store: store)
        model.revoke = { _ in }
        let asked = Gate()
        let answer = Gate()
        model.refresh = { [renewed = token()] _, _ in
            asked.open()
            await answer.wait()
            return renewed
        }
        let calls = Calls()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        model.upload(file, metadata: metadata)
        await asked.reached()
        await model.disconnect()
        answer.open()
        await drain(model)

        #expect(store.load() == nil)
        #expect(model.account == .disconnected)
        #expect(calls.all.isEmpty)
        #expect(posted.all.first?.body.hasPrefix("YouTube isn't connected.") == true)
    }

    /// A transfer begun on a sign-in that is being withdrawn would be cut off by the withdrawal
    /// — so an upload that meets a disconnect waits to see how it ends, and here it succeeds.
    @Test func nothingIsSentOnASignInThatADisconnectThenWithdraws() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token(expiresIn: 30))
        let (model, posted) = makeModel(store: store)
        let asked = Gate()
        let answer = Gate()
        model.refresh = { [renewed = token()] _, _ in
            asked.open()
            await answer.wait()
            return renewed
        }
        let revoking = Gate()
        let revoked = Gate()
        model.revoke = { _ in
            revoking.open()
            await revoked.wait()
        }
        let calls = Calls()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        model.upload(file, metadata: metadata)
        await asked.reached()
        let disconnect = Task { await model.disconnect() }
        await revoking.reached()
        answer.open()
        for _ in 0..<200 { await Task.yield() }
        #expect(calls.all.isEmpty)              // nothing is sent while the outcome is open
        #expect(posted.all.isEmpty)             // and nothing is said yet either

        revoked.open()
        await disconnect.value
        await drain(model)
        #expect(calls.all.isEmpty)
        #expect(posted.all.first?.body.hasPrefix("YouTube isn't connected.") == true)
        #expect(store.load() == nil)
        #expect(model.account == .disconnected)
    }

    /// Google can fail to be told, and then the account is still connected: an upload that was
    /// turned away on the guess that the disconnect would succeed was turned away for nothing.
    @Test func anUploadThatMeetsADisconnectThatFailsGoesAhead() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        let revoking = Gate()
        let revoked = Gate()
        model.revoke = { _ in
            revoking.open()
            await revoked.wait()
            throw URLError(.notConnectedToInternet)
        }
        let calls = Calls()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        let disconnect = Task { await model.disconnect() }
        await revoking.reached()
        #expect(model.account == .disconnecting)
        model.upload(file, metadata: metadata)
        for _ in 0..<200 { await Task.yield() }
        #expect(calls.all.isEmpty)

        revoked.open()
        await disconnect.value
        await drain(model)
        #expect(model.account == .connected(expires: nil))
        #expect(calls.all.count == 1)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
    }

    /// The sign-in Google dropped is the one the upload began under, which need not be the one
    /// saved by the time the answer arrives.
    @Test func aDroppedSignInDoesNotEndTheOneThatReplacedIt() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = InMemoryTokenStore(token(expiresIn: -10))
        let (model, _) = makeModel(store: store)
        model.revoke = { _ in }
        let asked = Gate()
        let answer = Gate()
        model.refresh = { _, _ in
            asked.open()
            await answer.wait()
            throw GoogleSignInError.signInExpired
        }
        var second = token()
        second.accessToken = "second"
        model.signIn = { [second] _, _ in second }

        model.upload(file, metadata: metadata)
        await asked.reached()
        await model.disconnect()
        await model.connectAndWait()
        answer.open()
        await drain(model)

        #expect(model.account == .connected(expires: nil))
        #expect(store.load()?.accessToken == "second")
        #expect(model.lastFailure == nil)
    }

    @Test func anUploadWithNoSignInSendsNothingAndSaysSo() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore())
        let calls = Calls()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(calls.all.isEmpty)
        #expect(posted.all.first?.body.hasPrefix("YouTube isn't connected.") == true)
    }

    @Test func aFailedUploadSaysWhyAndStaysConnected() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()))
        model.uploadFunction = { _, _, _, _ in throw URLError(.networkConnectionLost) }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(posted.all.map(\.title) == ["Couldn't upload to YouTube"])
        // Met once and not waited for: "could not reach", never "did not come back".
        #expect(
            posted.all.first?.body
                == "Couldn't reach YouTube. Check the connection and upload again. Try Again is in the menu. The clip is saved as \(file.lastPathComponent).")
        #expect(model.account == .connected(expires: nil))
        #expect(model.uploadInProgress == nil)
    }

    // MARK: - The channel's name

    /// The upload-only permission cannot ask which channel it is; the first upload says.
    @Test func theChannelIsLearnedFromAnUploadAndKeptAcrossLaunches() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        let store = InMemoryTokenStore(token())
        let (model, _) = makeModel(store: store, defaults: defaults)
        #expect(model.channelTitle == nil)
        model.uploadFunction = { [video = video()] _, _, _, _ in video }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(model.channelTitle == "My channel")
        #expect(defaults.string(forKey: "youtubeChannel") == "My channel")
        let relaunched = UploadModel(credentials: credentials, store: store, defaults: defaults)
        #expect(relaunched.channelTitle == "My channel")
    }

    /// The name belongs to the sign-in: a different account must not inherit the last one's.
    @Test func disconnectingForgetsTheChannel() async throws {
        let defaults = TestDefaults.make()
        defaults.set("My channel", forKey: "youtubeChannel")
        let model = UploadModel(
            credentials: credentials, store: InMemoryTokenStore(token()), defaults: defaults)
        #expect(model.channelTitle == "My channel")
        model.revoke = { _ in }

        await model.disconnect()

        #expect(model.channelTitle == nil)
        #expect(defaults.string(forKey: "youtubeChannel") == nil)
    }

    /// The video still landed, so that is said — but its channel is the account that has gone.
    @Test func anUploadThatOutlivesItsSignInLeavesNoChannelName() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        let (model, posted) = makeModel(store: InMemoryTokenStore(token()), defaults: defaults)
        model.revoke = { _ in }
        let started = Gate()
        let finish = Gate()
        model.uploadFunction = { [video = video()] _, _, _, _ in
            started.open()
            await finish.wait()
            return video
        }

        model.upload(file, metadata: metadata)
        await started.reached()
        await model.disconnect()
        finish.open()
        await drain(model)

        #expect(model.channelTitle == nil)
        #expect(defaults.string(forKey: "youtubeChannel") == nil)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
    }

    @Test func anAnswerThatNamesNoChannelKeepsTheNameAlreadyKnown() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        defaults.set("My channel", forKey: "youtubeChannel")
        let (model, _) = makeModel(store: InMemoryTokenStore(token()), defaults: defaults)
        model.uploadFunction = { [video = video(channel: nil)] _, _, _, _ in video }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(model.channelTitle == "My channel")
        #expect(defaults.string(forKey: "youtubeChannel") == "My channel")
    }

    @Test func aNameWithNoSignInBehindItIsNotShown() {
        let defaults = TestDefaults.make()
        defaults.set("Stale", forKey: "youtubeChannel")
        let model = UploadModel(credentials: credentials, store: InMemoryTokenStore(), defaults: defaults)
        #expect(model.channelTitle == nil)
    }

    // MARK: - From the Trim window to the uploader

    private func makeState(store: any TokenStore) -> AppState {
        AppState(
            defaults: TestDefaults.make(),
            uploads: UploadModel(credentials: credentials, store: store))
    }

    /// The export is `Export & Copy`'s own, and what it wrote is what goes up — with the export
    /// posting nothing of its own, since the upload's notice is the outcome.
    @Test func aClipIsExportedThenUploadedWithOneNotice() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        let state = makeState(store: InMemoryTokenStore(token()))
        let posted = Posted()
        state.notifier = { posted.append($0) }
        let exported = Exported()
        state.exports.exportFunction = { source, _, _, range, crop, _ in
            exported.record(source: source, range: range, crop: crop)
            return written
        }
        let calls = Calls()
        state.uploads.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }
        let source = URL(fileURLWithPath: "/tmp/Clip.mov")
        let range = ExportRange(start: 2, end: 5)
        let crop = CropRect(x: 10, y: 20, width: 640, height: 400)

        state.uploadClip(source, range: range, crop: crop, metadata: metadata)
        while state.exports.exportInProgress != nil { await Task.yield() }
        await drain(state.uploads)

        #expect(exported.all.count == 1)
        #expect(exported.all.first?.source == source)
        #expect(exported.all.first?.range == range)
        #expect(exported.all.first?.crop == crop)
        #expect(calls.all.map(\.file) == [written])
        #expect(calls.all.first?.metadata == metadata)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
    }

    /// Nothing to send, so nothing is sent — and the failure reported is the export's.
    @Test func aFailedExportUploadsNothing() async {
        let state = makeState(store: InMemoryTokenStore(token()))
        let posted = Posted()
        state.notifier = { posted.append($0) }
        state.exports.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }
        let calls = Calls()
        state.uploads.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken.token)
            return video
        }

        state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
        while state.exports.exportInProgress != nil { await Task.yield() }
        await drain(state.uploads)

        #expect(calls.all.isEmpty)
        #expect(posted.all.map(\.title) == ["Couldn't export to MP4"])
    }
}
