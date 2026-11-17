import Foundation
import Testing

@testable import UploadCore

/// The resumable upload against scripted answers (M40-T1): what is asked of YouTube, and what each
/// of its answers is taken to mean.
@Suite struct UploaderTests {

    private let session = UploadSession(
        url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=abc")!,
        fileSize: 1000, contentType: "video/mp4")
    private let metadata = VideoMetadata(title: "A clip", description: "About it", privacy: .unlisted)
    private let resource = #"{"id":"dQw4w9WgXcQ","snippet":{"title":"A clip","channelTitle":"My channel"},"status":{"privacyStatus":"unlisted","uploadStatus":"uploaded"}}"#

    /// A real file, because the uploader reads its size from disk.
    private func makeFile(bytes: Int = 1000) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uploadcore-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    /// An uploader whose waits cost nothing, so the patience is tested without living through it.
    private func instant(_ transport: ScriptedTransport) -> YouTubeUploader {
        YouTubeUploader(transport: transport, settleDelay: .zero, sleep: { _ in })
    }

    // MARK: - Opening a session

    /// 🔴 Left out, YouTube publishes as public — so no visibility may ever fail to reach the body.
    @Test(arguments: VideoMetadata.Privacy.allCases)
    func theSessionRequestAlwaysCarriesAVisibility(privacy: VideoMetadata.Privacy) throws {
        let request = YouTubeUploader.sessionRequest(
            metadata: VideoMetadata(title: "T", privacy: privacy), fileSize: 10,
            contentType: "video/mp4", accessToken: "at")
        let body = try JSONDecoder().decode(
            [String: [String: String]].self, from: try #require(request.httpBody))
        #expect(body["status"]?["privacyStatus"] == privacy.rawValue)
    }

    @Test func theSessionRequestDescribesTheVideoAndTheFile() throws {
        let request = YouTubeUploader.sessionRequest(
            metadata: metadata, fileSize: 1000, contentType: "video/mp4", accessToken: "at")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/upload/youtube/v3/videos")
        #expect(request.queryItems == ["uploadType": "resumable", "part": "snippet,status"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer at")
        #expect(request.value(forHTTPHeaderField: "X-Upload-Content-Length") == "1000")
        #expect(request.value(forHTTPHeaderField: "X-Upload-Content-Type") == "video/mp4")
        let body = try JSONDecoder().decode(
            [String: [String: String]].self, from: try #require(request.httpBody))
        #expect(body["snippet"] == ["title": "A clip", "description": "About it"])
    }

    @Test func openingASessionReturnsWhereToSendTheFile() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString])
        ])
        let opened = try await YouTubeUploader(transport: transport)
            .openSession(for: file, metadata: metadata, accessToken: "at")
        #expect(opened == session)
    }

    @Test func aSessionWithNoLocationIsMalformed() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([.response(status: 200)])
        await #expect(throws: YouTubeError.malformedResponse) {
            try await YouTubeUploader(transport: transport)
                .openSession(for: file, metadata: metadata, accessToken: "at")
        }
    }

    /// Measured at the link's target, because that is what the transfer reads.
    @Test func aSymlinkIsMeasuredAtItsTarget() throws {
        let file = try makeFile(bytes: 1234)
        let link = file.deletingLastPathComponent()
            .appendingPathComponent("uploadcore-link-\(UUID().uuidString).mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: file)
        }
        #expect(try YouTubeUploader.fileSize(of: link) == 1234)
    }

    @Test func whatIsNotANonEmptyFileIsNothingToUpload() throws {
        let empty = try makeFile(bytes: 0)
        defer { try? FileManager.default.removeItem(at: empty) }
        for url in [
            empty, FileManager.default.temporaryDirectory,
            URL(fileURLWithPath: "/nonexistent/clip.mp4"),
        ] {
            #expect(throws: YouTubeError.unreadableFile) { try YouTubeUploader.fileSize(of: url) }
        }
    }

    @Test func theContentTypeFollowsTheExtension() {
        #expect(YouTubeUploader.contentType(for: URL(fileURLWithPath: "/a/clip.MP4")) == "video/mp4")
        #expect(YouTubeUploader.contentType(for: URL(fileURLWithPath: "/a/take.mov")) == "video/quicktime")
        #expect(YouTubeUploader.contentType(for: URL(fileURLWithPath: "/a/other.bin")) == "application/octet-stream")
    }

    // MARK: - Sending

    @Test func sendingFromTheStartNamesNoRange() {
        let request = YouTubeUploader.sendRequest(session: session, offset: 0, accessToken: "at")
        #expect(request.httpMethod == "PUT")
        #expect(request.url == session.url)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "1000")
        #expect(request.value(forHTTPHeaderField: "Content-Range") == nil)
    }

    @Test func sendingFromAnOffsetNamesExactlyTheBytesThatFollow() {
        let request = YouTubeUploader.sendRequest(session: session, offset: 400, accessToken: "at")
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "600")
        #expect(request.value(forHTTPHeaderField: "Content-Range") == "bytes 400-999/1000")
    }

    @Test func aFinishedSendDecodesTheVideo() async throws {
        let transport = ScriptedTransport([.response(status: 200, body: resource)])
        let video = try await YouTubeUploader(transport: transport)
            .send(URL(fileURLWithPath: "/unused"), to: session, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(video.title == "A clip")
        #expect(video.privacyStatus == "unlisted")
        #expect(video.uploadStatus == "uploaded")
        #expect(video.channelTitle == "My channel")
        #expect(video.link == "https://youtu.be/dQw4w9WgXcQ")
    }

    /// The transport counts one request's bytes; a bar has to show the file's.
    @Test func progressCountsFromTheStartOfTheFile() async throws {
        let transport = ScriptedTransport([.response(status: 201, body: resource)])
        transport.bytesReported = 250
        let seen = Seen()
        _ = try await YouTubeUploader(transport: transport).send(
            URL(fileURLWithPath: "/unused"), to: session, from: 400, accessToken: "at"
        ) { seen.record($0) }
        #expect(seen.values == [650])
    }

    /// The session's opening is the moment YouTube starts holding an entry for the video, and a
    /// caller has to be told before it can be told anything else. A refused session reports nothing.
    @Test func theFirstReportComesAsTheSessionOpens() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString]),
            .response(status: 201, body: resource),
        ])
        transport.bytesReported = 1000
        let seen = Seen()
        _ = try await YouTubeUploader(transport: transport)
            .upload(file, metadata: metadata, accessToken: "at") { seen.record($0) }
        #expect(seen.values == [0, 1000])

        let refused = ScriptedTransport([.response(status: 403, body: "{}")])
        let unseen = Seen()
        await #expect(throws: YouTubeError.self) {
            _ = try await YouTubeUploader(transport: refused)
                .upload(file, metadata: metadata, accessToken: "at") { unseen.record($0) }
        }
        #expect(unseen.values.isEmpty)
    }

    // MARK: - Asking how far it got

    @Test func theStatusRequestIsAnEmptyPutNamingTheWholeFile() {
        let request = YouTubeUploader.statusRequest(session: session, accessToken: "at")
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Range") == "bytes */1000")
        #expect(request.httpBody?.isEmpty == true)
    }

    @Test func aRangeAnswerNamesTheNextByteToSend() {
        #expect(YouTubeUploader.nextOffset(afterRange: "bytes=0-399") == 400)
        #expect(YouTubeUploader.nextOffset(afterRange: "bytes=0-0") == 1)
        // No header: YouTube holds nothing yet.
        #expect(YouTubeUploader.nextOffset(afterRange: nil) == 0)
    }

    /// Guessing an offset would splice the file wrong, so an unreadable header is an error.
    @Test func aRangeThisCannotReadIsNotGuessedAt() {
        for header in ["bytes=5-10", "bytes=0-", "0-399", "bytes=0--1", "junk"] {
            #expect(YouTubeUploader.nextOffset(afterRange: header) == nil, "\(header)")
        }
    }

    @Test func anIncompleteUploadReportsWhereToResume() async throws {
        let transport = ScriptedTransport([.response(status: 308, headers: ["Range": "bytes=0-399"])])
        let status = try await YouTubeUploader(transport: transport)
            .status(of: session, accessToken: "at")
        #expect(status == .incomplete(nextOffset: 400))
    }

    @Test func anUploadThatFinishedReportsItsVideo() async throws {
        let transport = ScriptedTransport([.response(status: 200, body: resource)])
        let status = try await YouTubeUploader(transport: transport)
            .status(of: session, accessToken: "at")
        guard case .complete(let video) = status else {
            Issue.record("expected a finished upload")
            return
        }
        #expect(video.id == "dQw4w9WgXcQ")
    }

    // MARK: - The whole upload

    @Test func aTransferThatBreaksIsResumedFromWhereYouTubeGotTo() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString]),
            .failure(URLError(.networkConnectionLost)),
            .response(status: 308, headers: ["Range": "bytes=0-399"]),
            .response(status: 200, body: resource),
        ])
        let video = try await instant(transport)
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.map(\.offset) == [0, 400])
        #expect(
            transport.uploads.last?.request.value(forHTTPHeaderField: "Content-Range")
                == "bytes 400-999/1000")
    }

    /// The connection can die after the last byte landed; sending the file again would be a
    /// second video.
    @Test func aTransferThatBrokeAfterFinishingIsNotSentAgain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString]),
            .failure(URLError(.timedOut)),
            .response(status: 200, body: resource),
        ])
        let video = try await instant(transport)
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.count == 1)
    }

    /// The protocol's own list: these four statuses are interruptions, not answers.
    @Test(arguments: [500, 502, 503, 504])
    func aServerErrorMidUploadIsResumedLikeABrokenConnection(status: Int) async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString]),
            .response(status: status, body: "busy"),
            .response(status: 308, headers: ["Range": "bytes=0-599"]),
            .response(status: 201, body: resource),
        ])
        let video = try await instant(transport)
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.map(\.offset) == [0, 600])
    }

    /// Every byte held and still not finished: there is nothing to send, and a range starting
    /// past the end would be refused. Asking again is what completes it.
    @Test func anUploadHoldingEveryByteIsFinishedByAskingAgain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString]),
            .failure(URLError(.networkConnectionLost)),
            .response(status: 308, headers: ["Range": "bytes=0-999"]),
            .response(status: 200, body: resource),
        ])
        let video = try await instant(transport)
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.count == 1)
    }

    // MARK: - Patience (M40-T5)

    private let quarter = ScriptedTransport.Answer.response(status: 308, headers: ["Range": "bytes=0-249"])
    private let half = ScriptedTransport.Answer.response(status: 308, headers: ["Range": "bytes=0-499"])
    private let nothingHeld = ScriptedTransport.Answer.response(status: 308)
    private let dropped = ScriptedTransport.Answer.failure(URLError(.networkConnectionLost))

    private func open() -> ScriptedTransport.Answer {
        .response(status: 200, headers: ["Location": session.url.absoluteString])
    }

    /// A flaky line is not a dead one: as long as each try gets more bytes through, it goes on.
    @Test func aTransferKeepsBeingPickedUpWhileBytesKeepArriving() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            open(), dropped, quarter, dropped, half, dropped,
            .response(status: 308, headers: ["Range": "bytes=0-749"]),
            .response(status: 201, body: resource),
        ])
        let slept = Slept()
        let video = try await YouTubeUploader(transport: transport, sleep: { slept.record($0) })
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.map(\.offset) == [0, 250, 500, 750])
        // Each drop came after progress, so each wait is the first and shortest one.
        #expect(slept.durations == [.seconds(2), .seconds(2), .seconds(2)])
    }

    /// With nothing getting through, the waits grow and then run out — about five minutes —
    /// and what is thrown is the connection's own error, so the user is told it was the line.
    @Test func withNoProgressTheWaitsRunOutAndTheUploadGivesUp() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open()] + Array(repeating: dropped, count: 30))
        let slept = Slept()
        let error = await #expect(throws: UploadGaveUp.self) {
            try await YouTubeUploader(transport: transport, sleep: { slept.record($0) })
                .upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(error?.underlying is URLError)
        #expect(error.map { UploadFailure($0) } == .connectionLost)
        #expect(slept.durations == YouTubeUploader.waits)
        #expect(YouTubeUploader.patience == .seconds(302))
        #expect(YouTubeUploader.patienceMinutes == 5)
        #expect(transport.uploads.count == 1)   // nothing was re-sent blind
    }

    /// The patience is for silence, not for the whole upload: progress starts it over.
    @Test func progressStartsThePatienceOver() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let stalled = Array(repeating: dropped, count: 8)   // eight of the nine waits used up
        let transport = ScriptedTransport(
            [open(), dropped] + stalled + [quarter, dropped] + stalled + [half]
                + [.response(status: 201, body: resource)])
        let slept = Slept()
        let video = try await YouTubeUploader(transport: transport, sleep: { slept.record($0) })
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(slept.durations.count == 18)
        #expect(slept.durations[9] == .seconds(2))          // the first wait again, after progress
    }

    /// A server that keeps saying "busy" is waited out the same way, and named differently.
    @Test func aServerThatStaysBusyIsGivenUpOnAsYouTubesFault() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let busy = ScriptedTransport.Answer.response(status: 503, body: "busy")
        let transport = ScriptedTransport([open()] + Array(repeating: busy, count: 30))
        let error = await #expect(throws: UploadGaveUp.self) {
            try await self.instant(transport).upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(error.map { UploadFailure($0) } == .youTubeUnavailable)
    }

    private let offline = ScriptedTransport.Answer.failure(URLError(.notConnectedToInternet))

    /// With no connection the request never leaves the Mac, so opening can be tried again.
    @Test func aSessionIsWaitedForWhileThereIsNoConnectionAtAll() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([offline, offline, open(), .response(status: 201, body: resource)])
        let seen = Seen()
        let video = try await instant(transport)
            .upload(file, metadata: metadata, accessToken: { _ in "at" }, progress: { seen.record($0) })
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(seen.values.first == 0)   // said only once the session really opened
    }

    /// Opening is the request that creates the entry on the channel. If its answer is lost, or
    /// YouTube says "busy", the entry may exist already — so it is not asked for a second time.
    @Test(arguments: [URLError.Code.networkConnectionLost, .timedOut])
    func anOpeningWhoseAnswerWasLostIsNotRepeated(code: URLError.Code) async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([.failure(URLError(code)), open(), .response(status: 201, body: resource)])
        let error = await #expect(throws: URLError.self) {
            try await self.instant(transport).upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(transport.requests.count == 1)
        // Nothing was waited for, so it is not said to have "not come back".
        #expect(error.map { UploadFailure($0) } == .unreachable)
    }

    @Test func aBusyAnswerToTheOpeningIsNotRepeatedEither() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([.response(status: 503, body: "busy"), open()])
        let error = await #expect(throws: YouTubeError.self) {
            try await self.instant(transport).upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(transport.requests.count == 1)
        #expect(error.map { UploadFailure($0) } == .youTubeUnavailable)
    }

    /// Never having reached YouTube for the whole patience is "could not reach", not "dropped".
    @Test func aConnectionThatNeverComesIsReportedAsUnreachable() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport(Array(repeating: offline, count: 30))
        let slept = Slept()
        let error = await #expect(throws: URLError.self) {
            try await YouTubeUploader(transport: transport, sleep: { slept.record($0) })
                .upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(slept.durations == YouTubeUploader.waits)
        #expect(error.map { UploadFailure($0) } == .unreachable)
    }

    /// A clip deleted or changed mid-upload is this Mac's problem, not the line's: waiting five
    /// minutes for it and then blaming the connection would be wrong twice.
    @Test func aClipThatGoesMissingMidUploadEndsItAtOnce() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open(), dropped, quarter, .response(status: 201, body: resource)])
        let slept = Slept()
        let uploader = YouTubeUploader(transport: transport, sleep: {
            slept.record($0)
            try? FileManager.default.removeItem(at: file)   // gone while the transfer waits
        })
        let error = await #expect(throws: YouTubeError.unreadableFile) {
            try await uploader.upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(slept.durations.count == 1)
        #expect(transport.uploads.count == 1)
        #expect(error.map { UploadFailure($0) } == .clipMissing)
    }

    @Test func theCallerIsToldWhenTheTransferIsWaitingAndWhenItMovesAgain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open(), dropped, quarter, .response(status: 201, body: resource)])
        let states = States()
        _ = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, waiting: { states.record($0) })
        // Moving (open), moving (send), waiting (the drop), moving (resume).
        #expect(states.values == [false, false, true, false])
    }

    /// The token lasts an hour and an upload can last longer. One renewal is tried before a
    /// lapsed token is called a dead sign-in — and it costs no wait.
    @Test func aLapsedTokenIsRenewedOnceAndTheUploadGoesOn() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let lapsed = ScriptedTransport.Answer.response(status: 401, body: "{}")
        let transport = ScriptedTransport([
            open(), lapsed, quarter, .response(status: 201, body: resource),
        ])
        let slept = Slept()
        let asked = States()
        let video = try await YouTubeUploader(transport: transport, sleep: { slept.record($0) })
            .upload(file, metadata: metadata, accessToken: { renewed in
                asked.record(renewed)
                return renewed ? "fresh" : "stale"
            })
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(asked.values == [false, true])
        #expect(slept.durations.isEmpty)
        #expect(
            transport.uploads.last?.request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
        #expect(transport.uploads.map(\.offset) == [0, 250])
    }

    @Test func aTokenRefusedEvenWhenRenewedIsADeadSignIn() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let lapsed = ScriptedTransport.Answer.response(status: 401, body: "{}")
        let transport = ScriptedTransport([open(), lapsed, lapsed])
        let asked = States()
        let error = await #expect(throws: YouTubeError.notAuthorized) {
            try await self.instant(transport).upload(
                file, metadata: self.metadata,
                accessToken: { renewed in
                    asked.record(renewed)
                    return "at"
                })
        }
        #expect(asked.values == [false, true])   // renewed once, not over and over
        // Google renewed it and YouTube still said no: refused, not ended.
        #expect(error.map { UploadFailure($0) } == .signInRefused)
    }

    /// The renewal is a request too, and it can meet the same flaky line as the upload: it is
    /// waited out like any other step rather than ending the upload on the spot.
    @Test func aRenewalThatMeetsABrokenLineIsWaitedOut() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let lapsed = ScriptedTransport.Answer.response(status: 401, body: "{}")
        let transport = ScriptedTransport([open(), lapsed, quarter, .response(status: 201, body: resource)])
        let slept = Slept()
        let renewals = States()
        let video = try await YouTubeUploader(transport: transport, sleep: { slept.record($0) })
            .upload(file, metadata: metadata, accessToken: { renewed in
                guard renewed else { return "stale" }
                renewals.record(true)
                if renewals.values.count == 1 { throw URLError(.networkConnectionLost) }
                return "fresh"
            })
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(renewals.values.count == 2)
        #expect(slept.durations == [.seconds(2)])
    }

    /// The CLI hands over a token it cannot renew. A lapsed one fails there and then, without a
    /// pretend renewal and a second round of requests on the same dead token.
    @Test func aTokenThatCannotBeRenewedFailsWithoutASecondRound() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let lapsed = ScriptedTransport.Answer.response(status: 401, body: "{}")
        let transport = ScriptedTransport([open(), lapsed, lapsed])
        await #expect(throws: YouTubeError.notAuthorized) {
            try await self.instant(transport).upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(transport.requests.count == 1)   // the opening, and no status query after
        #expect(transport.uploads.count == 1)
    }

    /// `Cancel Upload` during a wait must not sit the wait out.
    @Test func cancellingDuringAWaitStopsAtOnce() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open(), dropped, quarter])
        let waiting = AsyncStream<Void>.makeStream()
        let uploader = YouTubeUploader(transport: transport, sleep: { _ in
            waiting.continuation.yield()
            try await Task.sleep(for: .seconds(60))
        })
        let upload = Task {
            try await uploader.upload(file, metadata: metadata, accessToken: "at")
        }
        for await _ in waiting.stream { break }
        upload.cancel()
        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(transport.uploads.count == 1)
    }

    /// A transfer that broke because it was cancelled is not an interruption to wait out: it
    /// must not be asked about and sent again, whatever the wait would have done.
    @Test func aCancelledTransferIsNotPickedUpAgain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            open(), dropped, quarter, .response(status: 201, body: resource),
        ])
        let uploader = instant(transport)
        let handle = TaskHandle()
        let ready = AsyncStream<Void>.makeStream()
        let upload = Task {
            for await _ in ready.stream { break }   // not before the handle below is set
            return try await uploader.upload(
                file, metadata: metadata, accessToken: { _ in "at" },
                // The session has just opened: cancel before the send that is about to break.
                progress: { if $0 == 0 { handle.cancel() } })
        }
        handle.set(upload)
        ready.continuation.yield()
        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(transport.uploads.count <= 1)
        #expect(transport.requests.count == 1)   // the session's opening, and no status query
    }

    // MARK: - Continuing an upload left unfinished (M40-T6)

    private let gone = ScriptedTransport.Answer.response(status: 404, body: "{}")

    /// The session an upload opens is the address it can be continued at later, so it is
    /// handed out the moment it exists.
    @Test func aFreshUploadSaysWhichSessionItOpened() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open(), .response(status: 201, body: resource)])
        let opened = Sessions()
        _ = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: nil,
            events: .init(opened: { opened.record($0) }))
        #expect(opened.all.map(\.url) == [session.url])
        #expect(opened.all.first?.fileSize == 1000)
    }

    /// Continuing asks first and sends only what is missing: no second session, so no second
    /// entry on the channel — the one the earlier attempt left becomes the video.
    @Test func aContinuedUploadAsksWhatYouTubeHoldsAndSendsTheRest() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([quarter, .response(status: 201, body: resource)])
        let opened = Sessions()
        let startedOver = States()
        let video = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: session,
            events: .init(opened: { opened.record($0) }, startedOver: { startedOver.record(true) }))
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.requests.count == 1)                        // the question, and no opening
        #expect(transport.requests.first?.httpMethod == "PUT")
        #expect(transport.uploads.map(\.offset) == [250])
        #expect(opened.all.isEmpty)
        #expect(startedOver.values.isEmpty)
    }

    @Test func aContinuedUploadYouTubeAlreadyFinishedSendsNothing() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([.response(status: 200, body: resource)])
        let video = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: session, events: .init())
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.isEmpty)
    }

    /// A session has a finite life. When the one to continue is gone, the upload begins again
    /// from nothing — and says so, because the earlier entry may still be on the channel.
    @Test func aContinuedUploadWhoseSessionIsGoneStartsOver() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([gone, open(), .response(status: 201, body: resource)])
        let opened = Sessions()
        let startedOver = States()
        let video = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: session,
            events: .init(opened: { opened.record($0) }, startedOver: { startedOver.record(true) }))
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(startedOver.values == [true])
        #expect(opened.all.count == 1)
        #expect(transport.uploads.map(\.offset) == [0])
    }

    /// Only a continued upload starts over. One whose own session vanishes mid-way has lost
    /// bytes it thought were safe, and that is a failure to report, not to paper over.
    @Test func anUploadWhoseOwnSessionVanishesIsNotQuietlyRestarted() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open(), dropped, gone, open()])
        let error = await #expect(throws: YouTubeError.sessionExpired) {
            try await self.instant(transport).upload(file, metadata: self.metadata, accessToken: "at")
        }
        #expect(transport.uploads.count == 1)
        #expect(error.map { UploadFailure($0) } == .sessionLost)
    }

    /// A clip that changed since the session was opened for it cannot go into that session —
    /// but it is a perfectly good clip, so it goes up from nothing instead of being refused.
    @Test func aContinuedUploadOfAClipThatChangedStartsOver() async throws {
        let file = try makeFile(bytes: 800)
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([open(), .response(status: 201, body: resource)])
        let startedOver = States()
        let video = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: session,
            events: .init(startedOver: { startedOver.record(true) }))
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(startedOver.values == [true])
        #expect(transport.requests.count == 1)                 // the opening; the old session is not asked
        #expect(transport.requests.first?.httpMethod == "POST")
        #expect(transport.uploads.map(\.offset) == [0])
    }

    /// "That upload is gone" has more than one spelling: a stale or cancelled session answers
    /// with whatever it likes. Any final word to the first question means begin again.
    @Test(arguments: [400, 403, 410, 499])
    func anyFinalAnswerAboutTheUploadToContinueStartsItOver(status: Int) async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([
            .response(status: status, body: "{}"), open(), .response(status: 201, body: resource),
        ])
        let startedOver = States()
        let video = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: session,
            events: .init(startedOver: { startedOver.record(true) }))
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(startedOver.values == [true])
    }

    /// An answer about the token, the quota or the server, or one that can't be read, is not
    /// an answer about the upload. Starting over on one would forget an upload YouTube may
    /// still hold — or, for a reply that was really "done", publish the clip twice.
    @Test(arguments: [
        [#"{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}"#: 403],
        [#"{"error":{"code":403,"errors":[{"reason":"uploadLimitExceeded"}]}}"#: 403],
        ["{}": 507],
        ["not a video": 200],
    ])
    func anAnswerAboutSomethingElseDoesNotStartAContinuedUploadOver(answer: [String: Int]) async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (body, status) = try #require(answer.first)
        let transport = ScriptedTransport([
            .response(status: status, body: body), open(), .response(status: 201, body: resource),
        ])
        let startedOver = States()
        await #expect(throws: (any Error).self) {
            try await self.instant(transport).upload(
                file, metadata: self.metadata, accessToken: { _ in "at" }, continuing: self.session,
                events: .init(startedOver: { startedOver.record(true) }))
        }
        #expect(startedOver.values.isEmpty)
        #expect(transport.requests.count == 1)                 // the question, and no new opening
    }

    /// A token refused even after it was renewed is the sign-in's trouble, not the upload's.
    @Test func aRefusedTokenDoesNotStartAContinuedUploadOver() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let lapsed = ScriptedTransport.Answer.response(status: 401, body: "{}")
        let transport = ScriptedTransport([lapsed, lapsed, open()])
        let startedOver = States()
        await #expect(throws: YouTubeError.notAuthorized) {
            try await self.instant(transport).upload(
                file, metadata: self.metadata, accessToken: { _ in "at" }, continuing: self.session,
                events: .init(startedOver: { startedOver.record(true) }))
        }
        #expect(startedOver.values.isEmpty)
        #expect(transport.requests.count == 2)
    }

    /// A busy server or a broken line is not an answer about the upload: it is waited out.
    @Test func aContinuedUploadWaitsOutABrokenLineBeforeItsFirstAnswer() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([dropped, quarter, .response(status: 201, body: resource)])
        let startedOver = States()
        let video = try await instant(transport).upload(
            file, metadata: metadata, accessToken: { _ in "at" }, continuing: session,
            events: .init(startedOver: { startedOver.record(true) }))
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(startedOver.values.isEmpty)
        #expect(transport.uploads.map(\.offset) == [250])
    }

    /// Once YouTube has answered for the upload being continued, it is this call's own: losing
    /// it later is a failure to report, as it is for an upload that was never continued.
    @Test func aContinuedUploadThatVanishesAfterAnsweringIsNotRestarted() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let transport = ScriptedTransport([quarter, dropped, gone, open()])
        let startedOver = States()
        await #expect(throws: YouTubeError.sessionExpired) {
            try await self.instant(transport).upload(
                file, metadata: self.metadata, accessToken: { _ in "at" }, continuing: self.session,
                events: .init(startedOver: { startedOver.record(true) }))
        }
        #expect(startedOver.values.isEmpty)
        #expect(transport.uploads.count == 1)
    }

    @Test func aFailureCanBeRetriedUnlessWhatStoppedItIsStillThere() {
        let again: [UploadFailure] = [
            .connectionLost, .unreachable, .youTubeUnavailable, .signInEnded, .signInRefused,
            .notConnected, .channelLimitReached, .projectQuotaSpent, .noChannel, .sessionLost, .other,
        ]
        let never: [UploadFailure] = [
            .clipMissing, .refusedTitle, .refusedDescription, .refused, .projectNotSetUp,
        ]
        for failure in again { #expect(failure.canRetry) }
        for failure in never { #expect(!failure.canRetry) }
    }

    // MARK: - The one list of failures

    @Test func everyFailureHasItsPlaceInTheList() {
        #expect(UploadFailure(GoogleSignInError.signInExpired) == .signInEnded)
        #expect(UploadFailure(YouTubeError.notAuthorized) == .signInRefused)
        // "It did not come back" is only true of something that was waited for.
        #expect(UploadFailure(UploadGaveUp(underlying: URLError(.timedOut))) == .connectionLost)
        #expect(
            UploadFailure(
                UploadGaveUp(underlying: YouTubeError.rejected(status: 502, reason: nil, message: nil)))
                == .youTubeUnavailable)
        #expect(UploadFailure(YouTubeError.uploadLimitExceeded) == .channelLimitReached)
        #expect(UploadFailure(YouTubeError.quotaExceeded) == .projectQuotaSpent)
        #expect(UploadFailure(YouTubeError.noChannel) == .noChannel)
        #expect(UploadFailure(YouTubeError.unreadableFile) == .clipMissing)
        #expect(UploadFailure(YouTubeError.sessionExpired) == .sessionLost)
        #expect(UploadFailure(YouTubeError.apiNotEnabled) == .projectNotSetUp)
        #expect(UploadFailure(URLError(.notConnectedToInternet)) == .unreachable)
        #expect(
            UploadFailure(YouTubeError.rejected(status: 400, reason: "invalidTitle", message: nil))
                == .refusedTitle)
        #expect(
            UploadFailure(YouTubeError.rejected(status: 400, reason: "invalidDescription", message: nil))
                == .refusedDescription)
        #expect(
            UploadFailure(YouTubeError.rejected(status: 400, reason: "invalidTags", message: nil))
                == .refused)
        #expect(
            UploadFailure(YouTubeError.rejected(status: 503, reason: nil, message: nil))
                == .youTubeUnavailable)
        #expect(UploadFailure(YouTubeError.malformedResponse) == .other)
        #expect(UploadFailure(CocoaError(.fileReadNoPermission)) == .other)
    }

    @Test func anOffsetPastTheEndOfTheFileIsNotTrusted() async {
        let transport = ScriptedTransport([.response(status: 308, headers: ["Range": "bytes=0-1000"])])
        await #expect(throws: YouTubeError.malformedResponse) {
            try await YouTubeUploader(transport: transport).status(of: session, accessToken: "at")
        }
    }

    /// YouTube answered; the same bytes would get the same answer.
    @Test func aRefusalIsNotRetried() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let quota = #"{"error":{"code":403,"message":"Exceeded.","errors":[{"reason":"quotaExceeded"}]}}"#
        let transport = ScriptedTransport([
            .response(status: 200, headers: ["Location": session.url.absoluteString]),
            .response(status: 403, body: quota),
        ])
        await #expect(throws: YouTubeError.quotaExceeded) {
            try await YouTubeUploader(transport: transport)
                .upload(file, metadata: metadata, accessToken: "at")
        }
        #expect(transport.requests.count == 1)
        #expect(transport.uploads.count == 1)
    }

    // MARK: - What YouTube's refusals mean

    private func error(_ status: Int, reason: String?) -> YouTubeError {
        let detail = reason.map { #"[{"reason":"\#($0)"}]"# } ?? "[]"
        return YouTubeError(
            status: status,
            body: Data(#"{"error":{"code":\#(status),"message":"Said why.","errors":\#(detail)}}"#.utf8))
    }

    /// The reason decides, not the status: a missing channel arrives as a 401 and reconnecting
    /// would never fix it.
    @Test func aRefusalIsReadByItsReason() {
        #expect(error(401, reason: "youtubeSignupRequired") == .noChannel)
        #expect(error(403, reason: "quotaExceeded") == .quotaExceeded)
        #expect(error(403, reason: "dailyLimitExceeded") == .quotaExceeded)
        #expect(error(400, reason: "uploadLimitExceeded") == .uploadLimitExceeded)
        #expect(error(403, reason: "accessNotConfigured") == .apiNotEnabled)
    }

    @Test func withoutAKnownReasonTheStatusDecides() {
        #expect(error(401, reason: "authError") == .notAuthorized)
        #expect(error(404, reason: nil) == .sessionExpired)
        #expect(
            error(400, reason: "invalidTitle")
                == .rejected(status: 400, reason: "invalidTitle", message: "Said why."))
        #expect(
            YouTubeError(status: 502, body: Data("<html>".utf8))
                == .rejected(status: 502, reason: nil, message: nil))
    }
}

/// Collects what a `@Sendable` progress closure was handed.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int64] = []

    func record(_ value: Int64) { lock.withLock { recorded.append(value) } }
    var values: [Int64] { lock.withLock { recorded } }
}

/// Collects the waits an uploader asked for.
private final class Slept: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    func record(_ value: Duration) { lock.withLock { recorded.append(value) } }
    var durations: [Duration] { lock.withLock { recorded } }
}

/// Collects the flags a `@Sendable` closure was handed.
private final class States: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []

    func record(_ value: Bool) { lock.withLock { recorded.append(value) } }
    var values: [Bool] { lock.withLock { recorded } }
}

/// Lets a closure cancel the task it runs in, once the test has the handle to give it.
private final class TaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<UploadedVideo, any Error>?

    func set(_ task: Task<UploadedVideo, any Error>) { lock.withLock { self.task = task } }
    func cancel() { lock.withLock { task?.cancel() } }
}

/// Collects the sessions an uploader said it opened.
private final class Sessions: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [UploadSession] = []

    func record(_ value: UploadSession) { lock.withLock { recorded.append(value) } }
    var all: [UploadSession] { lock.withLock { recorded } }
}
