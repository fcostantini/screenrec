import Foundation
import Network
import os

public enum LoopbackError: Error, Equatable {
    /// Nothing came back from the browser in time.
    case timedOut
    /// No port could be taken on 127.0.0.1.
    case notListening
}

/// Receives the one redirect a Google sign-in ends in — the loopback flow Google documents for
/// desktop apps. Listens on 127.0.0.1 at a port the system picks, answers the browser with a page
/// that says the browser's part is over, and hands back the redirect's query.
///
/// `@unchecked Sendable`: the listener and every connection are confined to `queue`.
final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let isExpected: @Sendable (String) -> Bool
    private let queue = DispatchQueue(label: "dev.fcostantini.screenrec.loopback")
    private let redirects: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    /// `isExpected` picks the redirect out of whatever else reaches the port. A request it turns
    /// down is answered 404 and never handed on, so it can neither finish a sign-in nor end one.
    init(accepting isExpected: @escaping @Sendable (String) -> Bool) throws {
        let parameters = NWParameters.tcp
        // Loopback only: nothing off this machine can reach the port.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        listener = try NWListener(using: parameters)
        self.isExpected = isExpected
        (redirects, continuation) = AsyncStream.makeStream()
    }

    deinit {
        stop()
    }

    /// Starts listening and returns the redirect URI to hand Google.
    func start() async throws -> String {
        try await withCheckedThrowingContinuation { ready in
            // The handler fires again on later state changes; only the first verdict resumes.
            let answered = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { [weak self] state in
                let verdict: Result<String, any Error>
                switch state {
                case .ready:
                    verdict = self?.listener.port.map {
                        .success("http://127.0.0.1:\($0.rawValue)")
                    } ?? .failure(LoopbackError.notListening)
                case .failed, .waiting:
                    verdict = .failure(LoopbackError.notListening)
                case .cancelled:
                    verdict = .failure(CancellationError())
                case .setup:
                    return
                @unknown default:
                    return
                }
                guard answered.withLock({ wasAnswered in
                    defer { wasAnswered = true }
                    return !wasAnswered
                }) else { return }
                // A listener that failed to start is not left half-alive behind the error.
                if case .failure = verdict { self?.listener.cancel() }
                ready.resume(with: verdict)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// The query of the first expected redirect to arrive.
    func redirectQuery(timeout: Duration) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [redirects] in
                for await query in redirects { return query }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LoopbackError.timedOut
            }
            defer { group.cancelAll() }
            guard let query = try await group.next() else { throw LoopbackError.timedOut }
            return query
        }
    }

    func stop() {
        listener.cancel()
        continuation.finish()
    }

    /// One read is enough: only the request line matters, and a browser's `GET` to loopback
    /// arrives whole.
    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [continuation, isExpected] data, _, _, _ in
            let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let query = Self.redirectQuery(inRequestHead: head).flatMap { isExpected($0) ? $0 : nil }
            // The query is handed on only once the page is sent, so a caller that stops the
            // receiver on its answer cannot cut the browser's page off.
            connection.send(
                content: Self.response(to: query),
                completion: .contentProcessed { _ in
                    connection.cancel()
                    if let query { continuation.yield(query) }
                })
        }
    }

    // MARK: - Pure halves

    /// The query of `GET /?…`, or nil for anything else a browser asks of the port — a favicon,
    /// a bare `/`.
    static func redirectQuery(inRequestHead head: String) -> String? {
        guard let line = head.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/?") else { return nil }
        let query = parts[1].dropFirst(2)
        return query.isEmpty ? nil : String(query)
    }

    /// The page says only what is true when it is served: the browser's part is over. Whether the
    /// sign-in took is decided afterwards, and said in the app.
    static func response(to query: String?) -> Data {
        guard let query else {
            return Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        }
        let finished = !query.split(separator: "&").contains { $0.hasPrefix("error=") }
        let headline = finished ? "Sign-in finished" : "Sign-in wasn\u{2019}t completed"
        let page = """
            <!doctype html><meta charset="utf-8"><meta name="color-scheme" content="light dark">
            <title>ScreenRec</title>
            <body style="font:16px -apple-system,sans-serif;margin:18vh auto;max-width:26em;text-align:center">
            <h2>\(headline)</h2><p>You can close this tab and go back to ScreenRec.</p></body>
            """
        let body = Data(page.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
