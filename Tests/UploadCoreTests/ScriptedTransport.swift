import Foundation

@testable import UploadCore

/// An `HTTPTransport` that answers from a script and records what it was asked — how every Google
/// response is exercised without a network.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    enum Answer {
        case response(status: Int, headers: [String: String] = [:], body: String = "")
        case failure(any Error)
    }

    struct Upload {
        let request: URLRequest
        let offset: Int64
    }

    private let lock = NSLock()
    private var answers: [Answer]
    private var sent: [URLRequest] = []
    private var uploaded: [Upload] = []
    /// What `upload` reports as sent before it answers.
    var bytesReported: Int64 = 0

    init(_ answers: [Answer]) {
        self.answers = answers
    }

    var requests: [URLRequest] { lock.withLock { sent } }
    var uploads: [Upload] { lock.withLock { uploaded } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(request) }
        return try next(for: request)
    }

    func upload(
        _ request: URLRequest, file: URL, offset: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { uploaded.append(Upload(request: request, offset: offset)) }
        progress(bytesReported)
        return try next(for: request)
    }

    private func next(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let answer = lock.withLock { answers.isEmpty ? nil : answers.removeFirst() }
        switch answer {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: headers)!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        case nil:
            throw URLError(.unknown)
        }
    }
}

extension URLRequest {
    /// A form body's fields, decoded.
    var formFields: [String: String] {
        let body = String(data: httpBody ?? Data(), encoding: .utf8) ?? ""
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1]).removingPercentEncoding
        }
        return fields
    }

    var queryItems: [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}
