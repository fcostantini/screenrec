import Foundation

public struct VideoMetadata: Equatable, Sendable {
    public enum Privacy: String, CaseIterable, Sendable {
        case `private`, unlisted, `public`
    }

    public var title: String
    public var description: String
    public var privacy: Privacy

    public init(title: String, description: String = "", privacy: Privacy) {
        self.title = title
        self.description = description
        self.privacy = privacy
    }
}

/// One resumable upload in flight: where to send the bytes, and how many there are.
public struct UploadSession: Equatable, Sendable {
    public let url: URL
    public let fileSize: Int64
    let contentType: String
}

public struct UploadedVideo: Equatable, Sendable {
    public let id: String
    public let title: String?
    public let privacyStatus: String?
    public let uploadStatus: String?
    public let channelTitle: String?

    /// Public so another module's stand-in for the uploader can answer with one.
    public init(
        id: String, title: String?, privacyStatus: String?, uploadStatus: String?,
        channelTitle: String?
    ) {
        self.id = id
        self.title = title
        self.privacyStatus = privacyStatus
        self.uploadStatus = uploadStatus
        self.channelTitle = channelTitle
    }

    public var link: String { Self.link(forID: id) }

    /// One definition of the address a video is shared by.
    public static func link(forID id: String) -> String { "https://youtu.be/\(id)" }
}

/// YouTube's resumable upload (developers.google.com/youtube/v3/guides/using_resumable_upload_protocol):
/// open a session with the metadata, send the file to the URL it returns, and after a broken
/// transfer ask how much arrived and send the rest.
public struct YouTubeUploader: Sendable {
    // Literal: a constant that parses once parses always.
    static let endpoint = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos")!

    /// What YouTube needs after a transfer breaks before it reports what it kept: asked at once it
    /// answers "nothing held", two seconds on it names the real byte (07, measured).
    public static let settleDelay = Duration.seconds(2)

    private let transport: any HTTPTransport
    private let settleDelay: Duration

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        settleDelay: Duration = YouTubeUploader.settleDelay
    ) {
        self.transport = transport
        self.settleDelay = settleDelay
    }

    public enum Status: Equatable, Sendable {
        case complete(UploadedVideo)
        case incomplete(nextOffset: Int64)
    }

    public func openSession(
        for file: URL, metadata: VideoMetadata, accessToken: String
    ) async throws -> UploadSession {
        let size = try Self.fileSize(of: file)
        let contentType = Self.contentType(for: file)
        let (data, response) = try await transport.send(
            Self.sessionRequest(
                metadata: metadata, fileSize: size, contentType: contentType,
                accessToken: accessToken))
        guard response.statusCode == 200 else {
            throw YouTubeError(status: response.statusCode, body: data)
        }
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location)
        else { throw YouTubeError.malformedResponse }
        return UploadSession(url: url, fileSize: size, contentType: contentType)
    }

    /// Sends `file` from `offset` to its end. `progress` reports the bytes Google has been sent in
    /// total, the offset included.
    public func send(
        _ file: URL, to session: UploadSession, from offset: Int64 = 0, accessToken: String,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> UploadedVideo {
        let (data, response) = try await transport.upload(
            Self.sendRequest(session: session, offset: offset, accessToken: accessToken),
            file: file, offset: offset
        ) { progress(offset + $0) }
        guard (200...201).contains(response.statusCode) else {
            throw YouTubeError(status: response.statusCode, body: data)
        }
        return try Self.video(from: data)
    }

    /// How far a transfer that just broke really got: waits `settleDelay`, then asks. Without the
    /// wait the answer is a stale zero, and the whole file would be sent again.
    public func statusAfterBreak(
        of session: UploadSession, accessToken: String
    ) async throws -> Status {
        try await Task.sleep(for: settleDelay)
        return try await status(of: session, accessToken: accessToken)
    }

    func status(of session: UploadSession, accessToken: String) async throws -> Status {
        let (data, response) = try await transport.send(
            Self.statusRequest(session: session, accessToken: accessToken))
        switch response.statusCode {
        case 200, 201:
            return .complete(try Self.video(from: data))
        case 308:
            guard let next = Self.nextOffset(
                afterRange: response.value(forHTTPHeaderField: "Range")),
                next <= session.fileSize
            else { throw YouTubeError.malformedResponse }
            return .incomplete(nextOffset: next)
        default:
            throw YouTubeError(status: response.statusCode, body: data)
        }
    }

    /// Finishes an upload whose status is known: nothing left to do, the rest of the file to send,
    /// or — when YouTube holds every byte and still hasn't finished — one more ask, which is what
    /// completes it.
    public func resume(
        _ file: URL, in session: UploadSession, from status: Status, accessToken: String,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> UploadedVideo {
        switch status {
        case .complete(let video):
            return video
        case .incomplete(let nextOffset) where nextOffset < session.fileSize:
            return try await send(
                file, to: session, from: nextOffset, accessToken: accessToken, progress: progress)
        case .incomplete:
            guard case .complete(let video) = try await statusAfterBreak(
                of: session, accessToken: accessToken)
            else { throw YouTubeError.malformedResponse }
            return video
        }
    }

    /// Opens a session and sends the file. A transfer that breaks is resumed **once**, from
    /// wherever YouTube says it got to.
    ///
    /// `progress` is first called, with `0`, the moment the session is open: from then on YouTube
    /// holds an entry for the video, finished or not (07), and a caller that stops has that to say.
    public func upload(
        _ file: URL, metadata: VideoMetadata, accessToken: String,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> UploadedVideo {
        let session = try await openSession(
            for: file, metadata: metadata, accessToken: accessToken)
        progress(0)
        do {
            return try await send(
                file, to: session, accessToken: accessToken, progress: progress)
        } catch {
            guard Self.isInterruption(error), !Task.isCancelled else { throw error }
            let status = try await statusAfterBreak(of: session, accessToken: accessToken)
            return try await resume(
                file, in: session, from: status, accessToken: accessToken, progress: progress)
        }
    }

    /// Whether a failed send left a transfer worth picking up: the connection broke, or YouTube
    /// answered with a status its protocol says to resume from. Any other answer is a refusal, and
    /// the same bytes would get it again.
    static func isInterruption(_ error: any Error) -> Bool {
        guard let answer = error as? YouTubeError else { return true }
        return answer.isInterruption
    }

    // MARK: - Requests

    /// 🔴 `status.privacyStatus` is always in the body: left out, YouTube publishes as `public`.
    static func sessionRequest(
        metadata: VideoMetadata, fileSize: Int64, contentType: String, accessToken: String
    ) -> URLRequest {
        var request = URLRequest(
            url: endpoint.appending(queryItems: [
                URLQueryItem(name: "uploadType", value: "resumable"),
                URLQueryItem(name: "part", value: "snippet,status"),
            ]))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue(contentType, forHTTPHeaderField: "X-Upload-Content-Type")
        let body: [String: [String: String]] = [
            "snippet": ["title": metadata.title, "description": metadata.description],
            "status": ["privacyStatus": metadata.privacy.rawValue],
        ]
        // A dictionary of strings cannot fail to encode.
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    static func sendRequest(
        session: UploadSession, offset: Int64, accessToken: String
    ) -> URLRequest {
        var request = URLRequest(url: session.url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(session.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(
            String(session.fileSize - offset), forHTTPHeaderField: "Content-Length")
        if offset > 0 {
            request.setValue(
                "bytes \(offset)-\(session.fileSize - 1)/\(session.fileSize)",
                forHTTPHeaderField: "Content-Range")
        }
        return request
    }

    /// An empty `PUT` that asks how much of the file Google holds.
    static func statusRequest(session: UploadSession, accessToken: String) -> URLRequest {
        var request = URLRequest(url: session.url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("bytes */\(session.fileSize)", forHTTPHeaderField: "Content-Range")
        request.httpBody = Data()
        return request
    }

    // MARK: - Answers

    /// The first byte Google still needs, from a `308`'s `Range: bytes=0-N`. No header means it
    /// holds nothing yet; nil means a header this can't read, where guessing would corrupt the file.
    static func nextOffset(afterRange range: String?) -> Int64? {
        guard let range else { return 0 }
        guard range.hasPrefix("bytes=0-"), let last = Int64(range.dropFirst("bytes=0-".count)),
              last >= 0
        else { return nil }
        return last + 1
    }

    static func video(from data: Data) throws -> UploadedVideo {
        guard let resource = try? JSONDecoder().decode(Resource.self, from: data) else {
            throw YouTubeError.malformedResponse
        }
        return UploadedVideo(
            id: resource.id, title: resource.snippet?.title,
            privacyStatus: resource.status?.privacyStatus,
            uploadStatus: resource.status?.uploadStatus,
            channelTitle: resource.snippet?.channelTitle)
    }

    static func contentType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        default: "application/octet-stream"
        }
    }

    /// The bytes an upload of `file` will send. A symlink is measured at its target, which is what
    /// the transfer reads.
    public static func fileSize(of file: URL) throws -> Int64 {
        let values = try? file.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size > 0 else {
            throw YouTubeError.unreadableFile
        }
        return Int64(size)
    }

    private struct Resource: Decodable {
        let id: String
        let snippet: Snippet?
        let status: Status?

        struct Snippet: Decodable {
            let title: String?
            let channelTitle: String?
        }

        struct Status: Decodable {
            let privacyStatus: String?
            let uploadStatus: String?
        }
    }
}
