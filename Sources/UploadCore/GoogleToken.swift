import Foundation

/// A Google sign-in: the short-lived access token and the refresh token that renews it. The only
/// thing the upload stores (ADR-024).
public struct GoogleToken: Codable, Equatable, Sendable {
    public var accessToken: String
    public var accessTokenExpiry: Date
    public var refreshToken: String
    /// When the refresh token itself lapses. Google sends this only for a Cloud project still in
    /// Testing, where it is 7 days (07); nil means no announced end.
    public var refreshTokenExpiry: Date?

    public init(
        accessToken: String, accessTokenExpiry: Date, refreshToken: String,
        refreshTokenExpiry: Date? = nil
    ) {
        self.accessToken = accessToken
        self.accessTokenExpiry = accessTokenExpiry
        self.refreshToken = refreshToken
        self.refreshTokenExpiry = refreshTokenExpiry
    }

    /// A minute of margin, so a token cannot lapse between this check and the request it guards.
    public func needsRefresh(now: Date = Date()) -> Bool {
        now >= accessTokenExpiry.addingTimeInterval(-60)
    }
}
