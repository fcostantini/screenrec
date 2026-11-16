import Foundation

/// What YouTube said no to, by the reason in its error body rather than the HTTP status alone —
/// `youtubeSignupRequired` arrives as a 401 and is not a sign-in problem.
public enum YouTubeError: Error, Equatable {
    /// The access token is no longer accepted.
    case notAuthorized
    /// The Google account has no YouTube channel.
    case noChannel
    /// The Cloud project's daily allowance is spent: 100 uploads, reset at midnight Pacific (07).
    case quotaExceeded
    /// The channel's own upload limit.
    case uploadLimitExceeded
    /// YouTube Data API v3 is not enabled on the Cloud project.
    case apiNotEnabled
    /// The session URL is gone: expired, or cancelled.
    case sessionExpired
    case rejected(status: Int, reason: String?, message: String?)
    case malformedResponse
    /// Nothing uploadable at that path: missing, empty, or not a regular file.
    case unreadableFile

    /// The statuses the resumable protocol says to resume from, where every other answer is final.
    var isInterruption: Bool {
        guard case .rejected(let status, _, _) = self else { return false }
        return [500, 502, 503, 504].contains(status)
    }

    init(status: Int, body: Data) {
        let failure = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        let reason = failure?.errors?.first?.reason
        switch reason {
        case "youtubeSignupRequired": self = .noChannel
        case "quotaExceeded", "dailyLimitExceeded": self = .quotaExceeded
        case "uploadLimitExceeded": self = .uploadLimitExceeded
        case "accessNotConfigured": self = .apiNotEnabled
        default:
            switch status {
            case 401: self = .notAuthorized
            case 404: self = .sessionExpired
            default: self = .rejected(status: status, reason: reason, message: failure?.message)
            }
        }
    }

    private struct Envelope: Decodable {
        let error: Failure
    }

    private struct Failure: Decodable {
        let message: String?
        let errors: [Detail]?
    }

    private struct Detail: Decodable {
        let reason: String?
    }
}
