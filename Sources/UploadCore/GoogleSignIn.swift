import Foundation

public enum GoogleSignInError: Error, Equatable {
    /// The user declined on Google's page.
    case denied
    /// Google sent some other `error=` back on the redirect.
    case refused(String)
    /// The redirect did not carry the `state` this sign-in sent — it is not ours.
    case stateMismatch
    case malformedRedirect
    /// Google granted less than the upload scope.
    case scopeNotGranted
    /// The refresh token no longer works: revoked, unused for six months, or past the 7 days a
    /// project in Testing allows.
    case signInExpired
    case rejected(error: String, description: String?)
    case malformedResponse
}

/// A Google sign-in for an installed app — the authorization URL, the redirect it comes back on,
/// and the token endpoint (developers.google.com/identity/protocols/oauth2/native-app).
public enum GoogleSignIn {
    /// Adds videos; cannot edit or delete what is already on the channel (ADR-024).
    static let uploadScope = "https://www.googleapis.com/auth/youtube.upload"

    // Literals: a constant that parses once parses always.
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// The whole sign-in, start to finish: listen on loopback, hand `open` the URL for the
    /// browser, wait for the redirect that is ours, and redeem it. Cancelling the task ends the wait.
    public static func signIn(
        credentials: GoogleClientCredentials,
        transport: any HTTPTransport = URLSessionTransport(),
        timeout: Duration = .seconds(300),
        open: @Sendable (URL) async throws -> Void
    ) async throws -> GoogleToken {
        let pkce = PKCE()
        let state = makeState()
        let receiver = try LoopbackReceiver { isRedirect($0, forState: state) }
        defer { receiver.stop() }
        let redirectURI = try await receiver.start()
        try await open(
            authorizationURL(
                clientID: credentials.clientID, redirectURI: redirectURI, pkce: pkce, state: state))
        let query = try await receiver.redirectQuery(timeout: timeout)
        let code = try authorizationCode(fromRedirectQuery: query, expectedState: state)
        return try await exchange(
            code: code, pkce: pkce, redirectURI: redirectURI, credentials: credentials,
            transport: transport)
    }

    /// An unguessable value the redirect must echo; `isRedirect` is how anything else is ignored.
    static func makeState() -> String {
        Data.random(count: 16).base64URLEncodedString()
    }

    /// No `access_type`: the installed-app flow returns a refresh token without it (07).
    static func authorizationURL(
        clientID: String, redirectURI: String, pkce: PKCE, state: String
    ) -> URL {
        authorizationEndpoint.appending(queryItems: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: uploadScope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ])
    }

    /// Whether a query reaching the loopback port answers the sign-in that sent `state` — what a
    /// `LoopbackReceiver` is told to accept, so nothing else can finish this sign-in or end it.
    static func isRedirect(_ query: String, forState state: String) -> Bool {
        value("state", in: query) == state
    }

    private static func value(_ name: String, in query: String) -> String? {
        URLComponents(string: "?" + query)?.queryItems?.first { $0.name == name }?.value
    }

    /// The authorization code in a redirect's query. `state` is judged first: a redirect that isn't
    /// this sign-in's has nothing to say about it, error or not.
    static func authorizationCode(
        fromRedirectQuery query: String, expectedState: String
    ) throws -> String {
        func value(_ name: String) -> String? { Self.value(name, in: query) }

        guard isRedirect(query, forState: expectedState) else {
            throw GoogleSignInError.stateMismatch
        }
        if let error = value("error") {
            throw error == "access_denied" ? GoogleSignInError.denied : .refused(error)
        }
        guard let code = value("code"), !code.isEmpty else {
            throw GoogleSignInError.malformedRedirect
        }
        return code
    }

    static func exchange(
        code: String, pkce: PKCE, redirectURI: String, credentials: GoogleClientCredentials,
        transport: any HTTPTransport, now: Date = Date()
    ) async throws -> GoogleToken {
        let response = try await token(
            [
                ("client_id", credentials.clientID),
                ("client_secret", credentials.clientSecret),
                ("code", code),
                ("code_verifier", pkce.verifier),
                ("grant_type", "authorization_code"),
                ("redirect_uri", redirectURI),
            ], transport: transport)
        guard let refreshToken = response.refreshToken, response.grants(uploadScope) else {
            // A grant this can't use must not stay live at Google with nothing here able to
            // withdraw it. Best effort: the error worth reporting is the grant's, not this call's.
            try? await revoke(response.accessToken, transport: transport)
            throw response.refreshToken == nil
                ? GoogleSignInError.malformedResponse : GoogleSignInError.scopeNotGranted
        }
        return GoogleToken(
            accessToken: response.accessToken,
            accessTokenExpiry: now.addingTimeInterval(response.expiresIn),
            refreshToken: refreshToken,
            refreshTokenExpiry: response.refreshTokenExpiresIn.map(now.addingTimeInterval))
    }

    /// A new access token for the same sign-in. Google returns no new refresh token here, so the
    /// one held is kept, with whatever end it was announced with.
    public static func refresh(
        _ token: GoogleToken, credentials: GoogleClientCredentials,
        transport: any HTTPTransport, now: Date = Date()
    ) async throws -> GoogleToken {
        let response: TokenResponse
        do {
            response = try await self.token(
                [
                    ("client_id", credentials.clientID),
                    ("client_secret", credentials.clientSecret),
                    ("refresh_token", token.refreshToken),
                    ("grant_type", "refresh_token"),
                ], transport: transport)
        } catch GoogleSignInError.rejected(error: "invalid_grant", _) {
            throw GoogleSignInError.signInExpired
        }
        var renewed = token
        renewed.accessToken = response.accessToken
        renewed.accessTokenExpiry = now.addingTimeInterval(response.expiresIn)
        if let remaining = response.refreshTokenExpiresIn {
            renewed.refreshTokenExpiry = now.addingTimeInterval(remaining)
        }
        return renewed
    }

    /// Withdraws the sign-in with Google. A token Google already considers invalid counts as
    /// revoked: the outcome the caller wanted is the one that holds.
    public static func revoke(_ token: GoogleToken, transport: any HTTPTransport) async throws {
        try await revoke(token.refreshToken, transport: transport)
    }

    private static func revoke(_ token: String, transport: any HTTPTransport) async throws {
        let (data, response) = try await transport.send(
            form(revocationEndpoint, [("token", token)]))
        guard response.statusCode != 200 else { return }
        let rejection = rejection(response, data)
        if case .rejected(error: "invalid_token", _) = rejection { return }
        throw rejection
    }

    /// Google's `{error, error_description}`, or the bare status when the body isn't that.
    private static func rejection(_ response: HTTPURLResponse, _ data: Data) -> GoogleSignInError {
        let failure = try? JSONDecoder().decode(TokenFailure.self, from: data)
        return .rejected(
            error: failure?.error ?? "http_\(response.statusCode)",
            description: failure?.errorDescription)
    }

    private static func token(
        _ fields: [(name: String, value: String)], transport: any HTTPTransport
    ) async throws -> TokenResponse {
        let (data, response) = try await transport.send(form(tokenEndpoint, fields))
        guard response.statusCode == 200 else { throw rejection(response, data) }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GoogleSignInError.malformedResponse
        }
        return decoded
    }

    private static func form(_ url: URL, _ fields: [(name: String, value: String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(fields)
        return request
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval
        let refreshToken: String?
        let refreshTokenExpiresIn: TimeInterval?
        let scope: String?

        /// `scope` is a space-separated list of what was granted.
        func grants(_ wanted: String) -> Bool {
            scope?.split(separator: " ").contains { $0 == wanted } ?? false
        }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case refreshTokenExpiresIn = "refresh_token_expires_in"
            case scope
        }
    }

    private struct TokenFailure: Decodable {
        let error: String
        let errorDescription: String?
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }
}
