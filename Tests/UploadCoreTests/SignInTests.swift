import Foundation
import Testing

@testable import UploadCore

/// The sign-in's pure halves (M40-T1): everything a Google page or endpoint can send back, without
/// a browser or a network.
@Suite struct SignInTests {

    private let credentials = GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret")
    private let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let granted = #""scope":"https://www.googleapis.com/auth/youtube.upload""#

    private func token(_ fields: String) -> ScriptedTransport.Answer {
        .response(status: 200, body: "{\(fields)}")
    }

    // MARK: - PKCE

    /// RFC 7636 Appendix B's own vector: a challenge Google can't verify is a sign-in that never ends.
    @Test func theChallengeMatchesTheRFCVector() {
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func aFreshVerifierIsURLSafeAndUnrepeated() {
        let first = PKCE().verifier
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(first.count == 43)
        #expect(first.unicodeScalars.allSatisfy(allowed.contains))
        #expect(first != PKCE().verifier)
    }

    // MARK: - The credentials file

    @Test func aDesktopClientsFileDecodes() throws {
        let json = #"{"installed":{"client_id":"abc.apps","client_secret":"xyz","redirect_uris":["http://localhost"]}}"#
        let decoded = try GoogleClientCredentials(json: Data(json.utf8))
        #expect(decoded == GoogleClientCredentials(clientID: "abc.apps", clientSecret: "xyz"))
    }

    /// A `web` client cannot take a loopback redirect, so it fails here rather than in the browser.
    @Test func anotherClientTypeIsRefused() {
        let json = #"{"web":{"client_id":"abc.apps","client_secret":"xyz"}}"#
        #expect(throws: GoogleClientCredentialsError.notADesktopClient) {
            try GoogleClientCredentials(json: Data(json.utf8))
        }
    }

    @Test func aFileThatIsNotGooglesIsUnreadable() {
        for text in ["", "not json", #"{"installed":{"client_id":"only"}}"#] {
            #expect(throws: GoogleClientCredentialsError.unreadable) {
                try GoogleClientCredentials(json: Data(text.utf8))
            }
        }
    }

    @Test func aMissingFileNamesItsPath() {
        let url = URL(fileURLWithPath: "/nonexistent/youtube-client.json")
        #expect(throws: GoogleClientCredentialsError.missing(url)) {
            try GoogleClientCredentials(contentsOf: url)
        }
    }

    /// Present and unreadable is a different problem from absent, with a different fix.
    @Test func aFileThatCannotBeReadIsNotCalledMissing() {
        let directory = FileManager.default.temporaryDirectory
        #expect {
            try GoogleClientCredentials(contentsOf: directory)
        } throws: { error in
            guard case GoogleClientCredentialsError.cannotRead(let url, _) = error else { return false }
            return url == directory
        }
    }

    // MARK: - The authorization URL

    @Test func theAuthorizationURLCarriesWhatGoogleNeeds() {
        let url = GoogleSignIn.authorizationURL(
            clientID: "id.apps", redirectURI: "http://127.0.0.1:5000", pkce: pkce, state: "st4te")
        let items = URLRequest(url: url).queryItems
        #expect(url.host == "accounts.google.com")
        #expect(items["client_id"] == "id.apps")
        #expect(items["redirect_uri"] == "http://127.0.0.1:5000")
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == GoogleSignIn.uploadScope)
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "st4te")
    }

    // MARK: - The redirect

    @Test func aRedirectYieldsItsCode() throws {
        let query = "state=st4te&code=4%2F0Ab_c-d&scope=https://www.googleapis.com/auth/youtube.upload"
        let code = try GoogleSignIn.authorizationCode(fromRedirectQuery: query, expectedState: "st4te")
        #expect(code == "4/0Ab_c-d")
    }

    /// Judged before anything else in the query: a request that isn't this sign-in's can neither
    /// complete it nor cancel it.
    @Test func aRedirectWithAnotherStateIsNotOurs() {
        for query in ["state=other&code=abc", "code=abc", "state=other&error=access_denied"] {
            #expect(throws: GoogleSignInError.stateMismatch) {
                try GoogleSignIn.authorizationCode(fromRedirectQuery: query, expectedState: "st4te")
            }
        }
    }

    /// What the loopback listener is told to accept: only a query carrying this sign-in's state.
    @Test func onlyAQueryWithThisSignInsStateIsItsRedirect() {
        #expect(GoogleSignIn.isRedirect("code=abc&state=st4te", forState: "st4te"))
        #expect(GoogleSignIn.isRedirect("error=access_denied&state=st4te", forState: "st4te"))
        for query in ["code=abc", "state=other&code=abc", "x=1", "state=st4teX"] {
            #expect(!GoogleSignIn.isRedirect(query, forState: "st4te"), "\(query)")
        }
    }

    @Test func aDeclinedConsentIsDenied() {
        #expect(throws: GoogleSignInError.denied) {
            try GoogleSignIn.authorizationCode(
                fromRedirectQuery: "error=access_denied&state=st4te", expectedState: "st4te")
        }
    }

    @Test func anyOtherErrorIsCarried() {
        #expect(throws: GoogleSignInError.refused("server_error")) {
            try GoogleSignIn.authorizationCode(
                fromRedirectQuery: "error=server_error&state=st4te", expectedState: "st4te")
        }
    }

    @Test func aRedirectWithNoCodeIsMalformed() {
        for query in ["state=st4te", "state=st4te&code="] {
            #expect(throws: GoogleSignInError.malformedRedirect) {
                try GoogleSignIn.authorizationCode(fromRedirectQuery: query, expectedState: "st4te")
            }
        }
    }

    // MARK: - The token endpoint

    /// The secret is not optional for a Desktop client (07), and the code has to survive its `/`.
    @Test func theExchangeSendsTheSecretTheVerifierAndTheCodeIntact() async throws {
        let transport = ScriptedTransport([
            token(#""access_token":"at","expires_in":3599,"refresh_token":"rt",\#(granted)"#)
        ])
        _ = try await GoogleSignIn.exchange(
            code: "4/0Ab+c", pkce: pkce, redirectURI: "http://127.0.0.1:5000",
            credentials: credentials, transport: transport, now: now)

        let request = try #require(transport.requests.first)
        #expect(request.url == GoogleSignIn.tokenEndpoint)
        #expect(request.httpMethod == "POST")
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("code=4%2F0Ab%2Bc") == true)
        let fields = request.formFields
        #expect(fields["client_id"] == "id.apps")
        #expect(fields["client_secret"] == "s3cret")
        #expect(fields["code"] == "4/0Ab+c")
        #expect(fields["code_verifier"] == pkce.verifier)
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["redirect_uri"] == "http://127.0.0.1:5000")
    }

    /// A project in Testing announces the refresh token's end; the token carries it so a surface
    /// can say so instead of failing a week later.
    @Test func theExchangeDatesBothTokens() async throws {
        let transport = ScriptedTransport([
            token(#""access_token":"at","expires_in":3599,"refresh_token":"rt","refresh_token_expires_in":604799,\#(granted)"#)
        ])
        let token = try await GoogleSignIn.exchange(
            code: "c", pkce: pkce, redirectURI: "r", credentials: credentials,
            transport: transport, now: now)
        #expect(token.accessToken == "at")
        #expect(token.refreshToken == "rt")
        #expect(token.accessTokenExpiry == now.addingTimeInterval(3599))
        #expect(token.refreshTokenExpiry == now.addingTimeInterval(604_799))
    }

    @Test func aPublishedProjectsSignInHasNoAnnouncedEnd() async throws {
        let transport = ScriptedTransport([
            token(#""access_token":"at","expires_in":3599,"refresh_token":"rt",\#(granted)"#)
        ])
        let token = try await GoogleSignIn.exchange(
            code: "c", pkce: pkce, redirectURI: "r", credentials: credentials,
            transport: transport, now: now)
        #expect(token.refreshTokenExpiry == nil)
    }

    /// Refused **and withdrawn**: a grant nothing here will keep must not stay live at Google.
    @Test func aGrantWithoutTheUploadScopeIsRefusedAndRevoked() async throws {
        for scope in [#""scope":"openid email""#, #""token_type":"Bearer""#] {
            let transport = ScriptedTransport([
                token(#""access_token":"at","expires_in":3599,"refresh_token":"rt",\#(scope)"#),
                .response(status: 200),
            ])
            await #expect(throws: GoogleSignInError.scopeNotGranted) {
                try await GoogleSignIn.exchange(
                    code: "c", pkce: pkce, redirectURI: "r", credentials: credentials,
                    transport: transport, now: now)
            }
            let revocation = try #require(transport.requests.last)
            #expect(revocation.url == GoogleSignIn.revocationEndpoint)
            #expect(revocation.formFields["token"] == "at")
        }
    }

    @Test func anExchangeWithNoRefreshTokenIsMalformedAndRevoked() async throws {
        let transport = ScriptedTransport([
            token(#""access_token":"at","expires_in":3599,\#(granted)"#),
            .response(status: 200),
        ])
        await #expect(throws: GoogleSignInError.malformedResponse) {
            try await GoogleSignIn.exchange(
                code: "c", pkce: pkce, redirectURI: "r", credentials: credentials,
                transport: transport, now: now)
        }
        #expect(transport.requests.last?.url == GoogleSignIn.revocationEndpoint)
    }

    /// The revoke is best effort: when it fails too, the error reported is still the grant's.
    @Test func anUnusableGrantIsReportedEvenIfRevokingItFails() async {
        let transport = ScriptedTransport([
            token(#""access_token":"at","expires_in":3599,\#(granted)"#),
            .failure(URLError(.notConnectedToInternet)),
        ])
        await #expect(throws: GoogleSignInError.malformedResponse) {
            try await GoogleSignIn.exchange(
                code: "c", pkce: pkce, redirectURI: "r", credentials: credentials,
                transport: transport, now: now)
        }
    }

    @Test func aRefusedExchangeCarriesGooglesReason() async {
        let transport = ScriptedTransport([
            .response(status: 400, body: #"{"error":"invalid_grant","error_description":"Bad Request"}"#)
        ])
        await #expect(throws: GoogleSignInError.rejected(error: "invalid_grant", description: "Bad Request")) {
            try await GoogleSignIn.exchange(
                code: "c", pkce: pkce, redirectURI: "r", credentials: credentials,
                transport: transport, now: now)
        }
    }

    // MARK: - Refresh and revoke

    private var held: GoogleToken {
        GoogleToken(
            accessToken: "old", accessTokenExpiry: now, refreshToken: "rt",
            refreshTokenExpiry: now.addingTimeInterval(500_000))
    }

    /// Google sends no refresh token on a refresh, so losing the held one would end the sign-in.
    @Test func aRefreshKeepsTheRefreshTokenAndItsEnd() async throws {
        let transport = ScriptedTransport([token(#""access_token":"new","expires_in":3599"#)])
        let renewed = try await GoogleSignIn.refresh(
            held, credentials: credentials, transport: transport, now: now)
        #expect(renewed.accessToken == "new")
        #expect(renewed.accessTokenExpiry == now.addingTimeInterval(3599))
        #expect(renewed.refreshToken == "rt")
        #expect(renewed.refreshTokenExpiry == held.refreshTokenExpiry)
        let fields = try #require(transport.requests.first).formFields
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["refresh_token"] == "rt")
        #expect(fields["client_secret"] == "s3cret")
    }

    @Test func aRefreshTokenGoogleNoLongerHonoursIsAnExpiredSignIn() async {
        let transport = ScriptedTransport([
            .response(status: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)
        ])
        await #expect(throws: GoogleSignInError.signInExpired) {
            try await GoogleSignIn.refresh(held, credentials: credentials, transport: transport, now: now)
        }
    }

    @Test func aTokenNearItsEndNeedsRefreshing() {
        #expect(held.needsRefresh(now: now))
        #expect(held.needsRefresh(now: now.addingTimeInterval(-30)))
        #expect(!held.needsRefresh(now: now.addingTimeInterval(-300)))
    }

    @Test func revokingSendsTheRefreshToken() async throws {
        let transport = ScriptedTransport([.response(status: 200)])
        try await GoogleSignIn.revoke(held, transport: transport)
        let request = try #require(transport.requests.first)
        #expect(request.url == GoogleSignIn.revocationEndpoint)
        #expect(request.formFields["token"] == "rt")
    }

    /// Already invalid is already revoked: disconnecting must not fail on the outcome it wanted.
    @Test func aTokenGoogleAlreadyDroppedCountsAsRevoked() async throws {
        for body in [
            #"{"error":"invalid_token"}"#,
            #"{"error":"invalid_token","error_description":"Token expired or revoked"}"#,
        ] {
            let transport = ScriptedTransport([.response(status: 400, body: body)])
            try await GoogleSignIn.revoke(held, transport: transport)
        }
    }

    @Test func anyOtherRevocationFailureIsReported() async {
        let transport = ScriptedTransport([.response(status: 503, body: "busy")])
        await #expect(throws: GoogleSignInError.rejected(error: "http_503", description: nil)) {
            try await GoogleSignIn.revoke(held, transport: transport)
        }
    }

    // MARK: - Form encoding

    @Test func formValuesAreEscapedStrictly() {
        let body = FormEncoding.encode([("a b", "x+y/z&w=1"), ("k", "plain-._~")])
        #expect(String(data: body, encoding: .utf8) == "a%20b=x%2By%2Fz%26w%3D1&k=plain-._~")
    }
}
