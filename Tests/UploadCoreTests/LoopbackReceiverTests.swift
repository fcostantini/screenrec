import Foundation
import Testing

@testable import UploadCore

/// The listener a sign-in's redirect lands on (M40-T1). The round trip stays on 127.0.0.1.
@Suite struct LoopbackReceiverTests {

    @Test func aRedirectsQueryIsRead() {
        let head = "GET /?state=abc&code=4/0Ab HTTP/1.1\r\nHost: 127.0.0.1:5000\r\n\r\n"
        #expect(LoopbackReceiver.redirectQuery(inRequestHead: head) == "state=abc&code=4/0Ab")
    }

    /// A browser asks for more than the redirect; none of it may be taken for one.
    @Test func anythingElseABrowserAsksForIsNotARedirect() {
        for head in [
            "GET /favicon.ico HTTP/1.1\r\n\r\n", "GET / HTTP/1.1\r\n\r\n", "GET /? HTTP/1.1\r\n\r\n",
            "POST /?code=abc HTTP/1.1\r\n\r\n", "", "garbage",
        ] {
            #expect(LoopbackReceiver.redirectQuery(inRequestHead: head) == nil, "\(head)")
        }
    }

    /// The page is served before the code is redeemed, so it may only say the browser is done.
    @Test func thePageClaimsOnlyThatTheBrowsersPartIsOver() throws {
        let finished = try #require(
            String(data: LoopbackReceiver.response(to: "state=a&code=b"), encoding: .utf8))
        #expect(finished.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(finished.contains("Sign-in finished"))
        #expect(!finished.localizedCaseInsensitiveContains("connected"))

        let declined = try #require(
            String(data: LoopbackReceiver.response(to: "error=access_denied&state=a"), encoding: .utf8))
        #expect(declined.contains("Sign-in wasn\u{2019}t completed"))

        let other = try #require(String(data: LoopbackReceiver.response(to: nil), encoding: .utf8))
        #expect(other.hasPrefix("HTTP/1.1 404"))
    }

    /// A request that isn't the sign-in's is told nothing and changes nothing: the wait goes on
    /// and the real redirect still lands.
    @Test func aStrayRequestIsTurnedAwayAndTheRealOneStillArrives() async throws {
        let receiver = try LoopbackReceiver { $0.contains("state=abc") }
        defer { receiver.stop() }
        let redirectURI = try await receiver.start()
        let session = URLSession(configuration: .ephemeral)
        async let query = receiver.redirectQuery(timeout: .seconds(10))

        let stray = try #require(URL(string: redirectURI + "/?state=other&code=evil"))
        let (_, strayResponse) = try await session.data(from: stray)
        #expect((strayResponse as? HTTPURLResponse)?.statusCode == 404)

        let real = try #require(URL(string: redirectURI + "/?state=abc&code=xyz"))
        _ = try await session.data(from: real)
        #expect(try await query == "state=abc&code=xyz")
    }

    @Test func aRealRequestToTheListenerComesBackAsItsQuery() async throws {
        let receiver = try LoopbackReceiver { _ in true }
        defer { receiver.stop() }
        let redirectURI = try await receiver.start()
        #expect(redirectURI.hasPrefix("http://127.0.0.1:"))

        let url = try #require(URL(string: redirectURI + "/?state=abc&code=xyz"))
        async let query = receiver.redirectQuery(timeout: .seconds(10))
        let (page, _) = try await URLSession(configuration: .ephemeral).data(from: url)

        #expect(try await query == "state=abc&code=xyz")
        #expect(String(data: page, encoding: .utf8)?.contains("Sign-in finished") == true)
    }

    @Test func aSignInNobodyFinishesTimesOut() async throws {
        let receiver = try LoopbackReceiver { _ in true }
        defer { receiver.stop() }
        _ = try await receiver.start()
        await #expect(throws: LoopbackError.timedOut) {
            try await receiver.redirectQuery(timeout: .milliseconds(50))
        }
    }
}
