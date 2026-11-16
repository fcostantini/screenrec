import Foundation

/// The one seam between this module and the network: production is `URLSessionTransport`, tests
/// script the answers.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Sends `file` from `offset` to its end as the request's body. `progress` reports the bytes
    /// sent **by this request**, so a caller resuming at an offset adds it.
    func upload(
        _ request: URLRequest, file: URL, offset: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        // Ephemeral: a sign-in's cookies and responses have no business on disk.
        session = URLSession(configuration: .ephemeral)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        return (data, try Self.http(response))
    }

    public func upload(
        _ request: URLRequest, file: URL, offset: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        let delegate = ProgressDelegate(progress)
        guard offset > 0 else {
            let (data, response) = try await session.upload(
                for: request, fromFile: file, delegate: delegate)
            return (data, try Self.http(response))
        }
        // A file stream honours an offset set before it opens, so a resume reads from disk like
        // the first attempt — no copy of the remainder, in memory or beside the file.
        guard let stream = InputStream(url: file),
              stream.setProperty(NSNumber(value: offset), forKey: .fileCurrentOffsetKey)
        else { throw URLError(.cannotOpenFile) }
        var request = request
        request.httpBodyStream = stream
        let (data, response) = try await session.data(for: request, delegate: delegate)
        return (data, try Self.http(response))
    }

    private static func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return http
    }
}

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @Sendable (Int64) -> Void

    init(_ report: @escaping @Sendable (Int64) -> Void) {
        self.report = report
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        report(totalBytesSent)
    }
}

/// `application/x-www-form-urlencoded`, strictly: everything outside RFC 3986's unreserved set is
/// escaped, so a `+` or `/` in an authorization code survives the trip.
enum FormEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ fields: [(name: String, value: String)]) -> Data {
        let pairs = fields.map { "\(escape($0.name))=\(escape($0.value))" }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
