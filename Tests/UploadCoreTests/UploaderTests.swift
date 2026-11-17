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
        let video = try await YouTubeUploader(transport: transport, settleDelay: .zero)
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
        let video = try await YouTubeUploader(transport: transport, settleDelay: .zero)
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
        let video = try await YouTubeUploader(transport: transport, settleDelay: .zero)
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
        let video = try await YouTubeUploader(transport: transport, settleDelay: .zero)
            .upload(file, metadata: metadata, accessToken: "at")
        #expect(video.id == "dQw4w9WgXcQ")
        #expect(transport.uploads.count == 1)
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
