import Foundation
import UploadCore

/// The words the YouTube account is described in (M40-T2, docs/06 "Settings › Sharing"). Pure, so
/// every state's copy is asserted without rendering a view.
public enum UploadCopy {

    public static func status(_ account: UploadModel.Account) -> String {
        switch account {
        case .unavailable: "Not available in this build"
        case .disconnected: "Not connected"
        case .connecting: "Waiting for Google in your browser…"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting…"
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
