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

    /// Public so whoever keeps a session to continue it later can also stand one in.
    public init(url: URL, fileSize: Int64, contentType: String) {
        self.url = url
        self.fileSize = fileSize
        self.contentType = contentType
    }
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

    /// How long `upload` waits before each try at picking a broken transfer up again, counted
    /// from the last byte that got through: two seconds — what YouTube needs anyway — doubling to
    /// a minute, about five minutes in all. When they run out it gives up.
    public static let waits: [Duration] = [2, 4, 8, 16, 32, 60, 60, 60, 60].map(Duration.seconds)

    /// The sum of `waits`, for whoever has to say how long that was.
    public static var patience: Duration { waits.reduce(.zero, +) }
    public static var patienceMinutes: Int { Int((patience / .seconds(60)).rounded()) }

    private let transport: any HTTPTransport
    private let settleDelay: Duration
    private let waits: [Duration]
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `waits` and `sleep` are injected so the patience is tested without living through it.
    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        settleDelay: Duration = YouTubeUploader.settleDelay,
        waits: [Duration] = YouTubeUploader.waits,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.settleDelay = settleDelay
        self.waits = waits
        self.sleep = sleep
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

    /// Opens a session and sends the file with a token that cannot be renewed: the CLI's way,
    /// and enough for anything shorter than the token's hour.
    public func upload(
        _ file: URL, metadata: VideoMetadata, accessToken: String,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> UploadedVideo {
        try await upload(
            file, metadata: metadata,
            accessToken: { renewed in
                guard !renewed else { throw YouTubeError.notAuthorized }
                return accessToken
            },
            progress: progress)
    }

    /// Opens a session and sends the file, picking a broken transfer up while bytes keep arriving
    /// and for `waits` after the last one (M40-T5). `accessToken(true)` is asked for once when
    /// YouTube says the token lapsed. `progress(0)` marks the session opening — from then on
    /// YouTube holds an entry (07) — and `waiting` says when the transfer is between tries.
    public func upload(
        _ file: URL, metadata: VideoMetadata,
        accessToken: @escaping @Sendable (_ renewed: Bool) async throws -> String,
        progress: @escaping @Sendable (Int64) -> Void = { _ in },
        waiting: @escaping @Sendable (Bool) -> Void = { _ in }
    ) async throws -> UploadedVideo {
        try await upload(
            file, metadata: metadata, accessToken: accessToken, continuing: nil,
            events: Events(progress: progress, waiting: waiting))
    }

    /// What `upload` says along the way, beyond the bytes: the session it opened — the address
    /// an unfinished upload can be continued at later — and that one it was asked to continue
    /// was gone, so it began again from nothing.
    public struct Events: Sendable {
        public var progress: @Sendable (Int64) -> Void
        public var waiting: @Sendable (Bool) -> Void
        public var opened: @Sendable (UploadSession) -> Void
        public var startedOver: @Sendable () -> Void

        public init(
            progress: @escaping @Sendable (Int64) -> Void = { _ in },
            waiting: @escaping @Sendable (Bool) -> Void = { _ in },
            opened: @escaping @Sendable (UploadSession) -> Void = { _ in },
            startedOver: @escaping @Sendable () -> Void = {}
        ) {
            self.progress = progress
            self.waiting = waiting
            self.opened = opened
            self.startedOver = startedOver
        }
    }

    /// The same, able to **continue** an upload an earlier call left unfinished (M40-T6): given
    /// its session, it asks YouTube how much it holds and sends the rest, so the entry that
    /// attempt left becomes the video. A session YouTube has let go of is started over.
    public func upload(
        _ file: URL, metadata: VideoMetadata,
        accessToken: @escaping @Sendable (_ renewed: Bool) async throws -> String,
        continuing: UploadSession?, events: Events
    ) async throws -> UploadedVideo {
        let progress = events.progress
        let waiting = events.waiting
        var token = try await accessToken(false)
        var renewal = Renewal.notTried
        var waitsLeft = waits[...]
        var session = continuing
        var continued = continuing != nil
        // The next byte YouTube needs, or nil before anything has been sent. A continued upload
        // starts by asking, so it begins as "nothing known to be held".
        var held: Int64? = continuing == nil ? nil : 0

        while true {
            do {
                // In here, so a renewal that meets the same flaky network is waited out too.
                if renewal == .wanted {
                    token = try await accessToken(true)
                    renewal = .done
                }
                // A clip that changed since the session to continue was opened for it cannot go
                // into that session, but it can still go up: from nothing.
                if continued, let open = session, try Self.fileSize(of: file) != open.fileSize {
                    throw NothingToContinue()
                }
                guard let open = session else {
                    let opened = try await openSession(
                        for: file, metadata: metadata, accessToken: token)
                    session = opened
                    waiting(false)
                    events.opened(opened)
                    progress(0)
                    continue
                }
                var from: Int64 = 0
                if let known = held {
                    let answer = try await status(of: open, accessToken: token)
                    // YouTube still knows the upload being continued: from here it is this
                    // call's own, and losing it later is a failure, not a reason to begin again.
                    continued = false
                    switch answer {
                    case .complete(let video):
                        return video
                    case .incomplete(let next):
                        if next > known {
                            // Bytes got through since the last look: the patience starts over.
                            waitsLeft = waits[...]
                            renewal = .notTried
                            held = next
                        }
                        // Every byte held and still unfinished: asking again is what completes it.
                        guard next < open.fileSize else { throw Unfinished() }
                        from = next
                    }
                }
                held = held ?? 0
                // The clip can have gone, or changed, since the session was opened for it.
                guard try Self.fileSize(of: file) == open.fileSize else {
                    throw YouTubeError.unreadableFile
                }
                waiting(false)   // only now: the status query has shown the line is back
                return try await send(
                    file, to: open, from: from, accessToken: token, progress: progress)
            } catch {
                try Task.checkCancellation()
                if case YouTubeError.notAuthorized = error, renewal == .notTried {
                    renewal = .wanted
                    continue
                }
                if continued, Self.meansNothingToContinue(error) {
                    // YouTube has let go of the upload being continued, or the clip is no
                    // longer the one it was opened for: begin again from nothing.
                    continued = false
                    session = nil
                    held = nil
                    waitsLeft = waits[...]
                    events.startedOver()
                    continue
                }
                // Opening is a `POST` that creates the entry: it is tried again only when the
                // first try cannot have reached YouTube, or a lost answer would leave two.
                let worthAnotherTry = session == nil
                    ? Self.neverReachedYouTube(error) : Self.isInterruption(error)
                guard worthAnotherTry else { throw error }
                guard let wait = waitsLeft.popFirst() else {
                    if error is Unfinished { throw YouTubeError.malformedResponse }
                    throw session == nil ? error : UploadGaveUp(underlying: error)
                }
                waiting(true)
                try await sleep(wait)
            }
        }
    }

    private enum Renewal {
        case notTried, wanted, done
    }

    /// YouTube holds the whole file and has not said the video exists yet.
    private struct Unfinished: Error {}

    /// The clip is not the one the session to continue was opened for.
    private struct NothingToContinue: Error {}

    /// Whether a continued upload's first question was answered that the upload is no more:
    /// gone, or refused outright. A refused token, a spent quota, a busy server or a reply that
    /// can't be read says nothing about it — and starting over on one could publish it twice.
    static func meansNothingToContinue(_ error: any Error) -> Bool {
        if error is NothingToContinue { return true }
        switch error as? YouTubeError {
        case .sessionExpired: return true
        case .rejected(let status, _, _): return (400...499).contains(status)
        default: return false
        }
    }

    /// Whether a failed step left a transfer worth picking up: the connection broke, or YouTube
    /// answered with a status its protocol says to resume from. A refusal would only be repeated,
    /// and a clip that can no longer be read is this Mac's problem, not the line's.
    static func isInterruption(_ error: any Error) -> Bool {
        switch error {
        case is Unfinished: true
        case let answer as YouTubeError: answer.isInterruption
        case let failure as URLError: !Self.notTheLine.contains(failure.code)
        default: false
        }
    }

    private static let notTheLine: Set<URLError.Code> = [
        .cancelled, .fileDoesNotExist, .cannotOpenFile, .noPermissionsToReadFile, .fileIsDirectory,
    ]

    /// The failures that happen before a request leaves this Mac.
    static func neverReachedYouTube(_ error: any Error) -> Bool {
        guard let failure = error as? URLError else { return false }
        return [
            .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .internationalRoamingOff, .dataNotAllowed,
        ].contains(failure.code)
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
