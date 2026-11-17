import Foundation
import RecorderCore
import UploadCore

/// The words the YouTube account is described in (M40-T2, docs/06 "Settings › Sharing"). Pure, so
/// every state's copy is asserted without rendering a view.
public enum UploadCopy {

    /// `channel` is the name YouTube returned with the last upload; until there has been one, the
    /// upload-only permission gives no way to ask.
    public static func status(_ account: UploadModel.Account, channel: String? = nil) -> String {
        switch account {
        case .unavailable: "Not available in this build"
        case .disconnected: "Not connected"
        case .connecting: waiting
        case .connected: channel.map { "Connected · \($0)" } ?? "Connected"
        case .disconnecting: "Disconnecting…"
        }
    }

    private static let waiting = "Waiting for Google in your browser…"

    // MARK: - The Trim window's row (docs/06 "Trim window")

    public enum TrimAction: Equatable, Sendable {
        /// Connected: the sheet.
        case upload
        /// Not connected: the alert that explains the browser step, then the sign-in.
        case connect
        /// A sign-in is in the browser: the button gives it up.
        case cancelSignIn
        /// Nothing this build or this moment can do.
        case none
    }

    public static func trimAction(_ account: UploadModel.Account, canSignIn: Bool) -> TrimAction {
        switch account {
        case .connected: canSignIn ? .upload : .none
        case .disconnected: .connect
        case .connecting: .cancelSignIn
        case .unavailable, .disconnecting: .none
        }
    }

    public static func trimButton(_ account: UploadModel.Account) -> String {
        account == .connecting ? "Cancel" : "Upload to YouTube…"
    }

    /// `profile` is the size `Export & Copy` quotes — `H.264 1920 × 1200` — and `cropped` whether a
    /// crop is drawn, so the two rows describe the same file.
    public static func trimCaption(
        for account: UploadModel.Account, failure: String?, canSignIn: Bool,
        profile: String, cropped: Bool
    ) -> String {
        if let failure { return failure }
        switch account {
        case .unavailable:
            return "This build has no YouTube credentials."
        case .connected where !canSignIn:
            return "This build has no YouTube credentials, so it can't use the saved sign-in."
        case .connected:
            let written = cropped ? "only the range, cropped" : "only the range"
            return "Uploads \(written) — \(profile) — to your YouTube channel. "
                + "Asks for a title first."
        case .disconnected:
            return "Uploads only the range to YouTube. You'll connect an account first."
        case .connecting:
            return waiting
        case .disconnecting:
            return "Disconnecting…"
        }
    }

    // MARK: - The connect alert and the sheet

    public static let connectTitle = "Connect YouTube to upload"
    /// Describes Google's warning rather than quoting it: its pages are translated, and worded
    /// differently for a project in testing and a published one (07).
    public static let connectMessage =
        "ScreenRec opens Google in your browser and asks for one permission: adding videos to "
        + "your channel. It can't edit or delete what is already there.\n\n"
        + "Google hasn't verified ScreenRec, so it warns you first. You can continue past the "
        + "warning. Disconnect at any time in Settings."
    public static let connectConfirm = "Continue in Browser"

    public static let sheetTitle = "Upload to YouTube"
    public static let sheetConfirm = "Upload"
    public static let longVideoWarning =
        "Longer than 15 minutes. YouTube only accepts this from a verified channel."

    public static func sheetDestination(channel: String?) -> String {
        let goes = channel.map { "Goes to “\($0)”." } ?? "Goes to the channel you connected."
        return "\(goes) YouTube's Terms of Service apply."
    }

    /// `0:24 · up to 18 MB · H.264 1920 × 1200`. The weight and the size are left out until the
    /// source's geometry has loaded rather than quoted from nothing.
    public static func sheetSummary(seconds: Double, bytes: Int64?, profile: String?) -> String {
        var parts = [Timecode.cutPoint(seconds)]
        if let bytes { parts.append("up to \(ApproximateBytes.formatted(bytes))") }
        if let profile { parts.append(profile) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Why an upload didn't happen

    static func uploadFailure(_ error: any Error) -> String {
        switch error {
        case GoogleSignInError.signInExpired, YouTubeError.notAuthorized:
            "YouTube needs reconnecting in Settings."
        case UploadModelError.notConnected:
            "YouTube isn't connected."
        case YouTubeError.quotaExceeded:
            "YouTube's daily upload limit for this build is used up."
        case YouTubeError.uploadLimitExceeded:
            "Your channel has reached YouTube's upload limit for today."
        case YouTubeError.noChannel:
            "This Google account has no YouTube channel."
        case YouTubeError.unreadableFile:
            "The exported file couldn't be read."
        case YouTubeError.rejected:
            "YouTube refused the upload."
        case is URLError:
            "The connection dropped."
        default:
            // Anything else may be this Mac's doing as easily as YouTube's.
            "The upload didn't finish."
        }
    }

    /// The line under the account row: a failure if the last attempt had one, else whatever the
    /// state itself has to say. Nil when there is nothing to add.
    public static func note(
        for account: UploadModel.Account, failure: String?, canSignIn: Bool,
        locale: Locale = .current
    ) -> String? {
        if let failure { return failure }
        switch account {
        case .unavailable:
            return "This build has no YouTube credentials."
        case .connected where !canSignIn:
            return "This build has no YouTube credentials, so it can't use this sign-in. "
                + "Disconnect removes it."
        case .connected(let end?):
            let day = end.formatted(.dateTime.day().month(.wide).locale(locale))
            return "This sign-in ends on \(day) because the Google project behind this build "
                + "is still in testing."
        case .disconnected, .connecting, .disconnecting, .connected(expires: nil):
            return nil
        }
    }

    /// The link that follows the note, when the note is one the README has the answer to.
    public static func noteLink(
        for account: UploadModel.Account, failure: String?, canSignIn: Bool
    ) -> String? {
        guard failure == nil else { return nil }
        switch account {
        case .unavailable: return "How to add them"
        case .connected where !canSignIn: return "How to add them"
        case .connected(expires: .some): return "What to do"
        case .disconnected, .connecting, .disconnecting, .connected(expires: nil): return nil
        }
    }

    public static func visibilityLabel(_ privacy: VideoMetadata.Privacy) -> String {
        switch privacy {
        case .unlisted: "Unlisted"
        case .private: "Private"
        case .public: "Public"
        }
    }

    public static func visibilityCaption(_ privacy: VideoMetadata.Privacy) -> String {
        switch privacy {
        case .unlisted: "Anyone with the link can watch. It isn't shown on your channel."
        case .private: "Only you can watch, so a link won't open for anyone else."
        case .public: "Anyone can find it and watch it on your channel."
        }
    }

    /// The order the picker offers them in: the default first, the widest last.
    public static let visibilityChoices: [VideoMetadata.Privacy] = [.unlisted, .private, .public]

    static let signInEnded = "The last sign-in has ended. Connect again."
    static let savedCopyNotRemoved =
        "Google ended the sign-in, but the saved copy couldn't be removed from this Mac."
    static let notWithdrawn =
        "The saved sign-in couldn't be read, so Google wasn't told. "
        + "You can remove ScreenRec's access in your Google account."

    static func connectFailure(_ error: any Error) -> String {
        switch error {
        case GoogleSignInError.denied:
            "Sign-in was cancelled in the browser."
        case UploadModelError.browserDidNotOpen:
            "Couldn't open the browser."
        case LoopbackError.timedOut:
            "Nothing came back from the browser in 5 minutes."
        case LoopbackError.notListening:
            "Couldn't listen for the sign-in on this Mac."
        case GoogleSignInError.scopeNotGranted:
            "Google didn't grant the upload permission."
        case is URLError:
            "Couldn't reach Google. Check the connection and try again."
        default:
            "The sign-in didn't complete. Try again."
        }
    }

    static func disconnectFailure(_ error: any Error) -> String {
        switch error {
        case is URLError:
            "Couldn't reach Google, so you are still connected."
        default:
            "Google couldn't end the sign-in just now, so you are still connected."
        }
    }

    /// Where the links under the section go. Literals: a constant that parses once parses always.
    public static let termsURL = URL(string: "https://www.youtube.com/t/terms")!
    public static let googlePrivacyURL = URL(string: "https://policies.google.com/privacy")!
    public static let whatIsSentURL = URL(
        string: "https://github.com/fcostantini/screenrec#what-screenrec-sends")!
    public static let credentialsHelpURL = URL(
        string: "https://github.com/fcostantini/screenrec#youtube-credentials")!
}
