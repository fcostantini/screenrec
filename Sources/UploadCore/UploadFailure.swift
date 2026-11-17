import Foundation

/// The uploader waited for a broken transfer for as long as it is willing to and gave up. A type
/// of its own, because only then is "it did not come back" true: the same error met once is
/// something that could not be reached, not something that was waited for.
public struct UploadGaveUp: Error {
    public let underlying: any Error

    public init(underlying: any Error) {
        self.underlying = underlying
    }
}

/// Why an upload did not land, as one list (M40-T5). The app and the CLI each put it into words
/// with an exhaustive `switch`, so a new case compiles in neither until both have something to say.
public enum UploadFailure: Equatable, Sendable {
    /// The connection dropped and did not come back within the uploader's patience.
    case connectionLost
    /// Google or YouTube could not be reached, and nothing was waited for.
    case unreachable
    /// YouTube answered with a server error, at once or for as long as the patience lasted.
    case youTubeUnavailable
    /// Google no longer honours the sign-in: removed in the account, or lapsed.
    case signInEnded
    /// YouTube refused a token Google had just renewed. The sign-in still stands at Google, so
    /// it is not dropped here — that would leave a live grant nothing local could end.
    case signInRefused
    /// There was no sign-in to upload with.
    case notConnected
    /// The channel's own daily upload limit.
    case channelLimitReached
    /// The Cloud project's daily allowance, shared by every copy of the same build.
    case projectQuotaSpent
    case noChannel
    /// Nothing to send at that path any more.
    case clipMissing
    case refusedTitle
    case refusedDescription
    /// YouTube said no and this list has no name for why.
    case refused
    /// YouTube no longer knows the unfinished upload: its session expired.
    case sessionLost
    /// The build's Cloud project has the YouTube service switched off.
    case projectNotSetUp
    case other

    public init(_ error: any Error) {
        switch error {
        case let gaveUp as UploadGaveUp:
            self = UploadFailure(gaveUp.underlying) == .youTubeUnavailable
                ? .youTubeUnavailable : .connectionLost
        case GoogleSignInError.signInExpired:
            self = .signInEnded
        case YouTubeError.notAuthorized:
            self = .signInRefused
        case YouTubeError.uploadLimitExceeded:
            self = .channelLimitReached
        case YouTubeError.quotaExceeded:
            self = .projectQuotaSpent
        case YouTubeError.noChannel:
            self = .noChannel
        case YouTubeError.unreadableFile:
            self = .clipMissing
        case YouTubeError.sessionExpired:
            self = .sessionLost
        case YouTubeError.apiNotEnabled:
            self = .projectNotSetUp
        case YouTubeError.rejected(let status, let reason, _):
            switch reason {
            case "invalidTitle": self = .refusedTitle
            case "invalidDescription": self = .refusedDescription
            default: self = (500...599).contains(status) ? .youTubeUnavailable : .refused
            }
        case is URLError:
            self = .unreachable
        default:
            self = .other
        }
    }
}
