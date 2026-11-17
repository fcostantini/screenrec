import Foundation
import Testing
import UploadCore

@testable import AppCore

/// The upload sheet's rules and words (M40-T3): what YouTube would refuse can't be typed, and
/// every state of the Trim window's row is asserted without rendering it.
@Suite struct UploadFormTests {

    // MARK: - The fields

    /// YouTube refuses both characters outright, in a title and in a description.
    @Test func angleBracketsNeverReachYouTube() {
        #expect(UploadForm.title("a <b> c > d") == "a b c  d")
        #expect(UploadForm.description("<script>x</script>") == "scriptx/script")
    }

    /// Its terms forbid a *shorter* limit than its own, so the cap is exactly 100 — and counted in
    /// characters, so an emoji is one.
    @Test func aTitleStopsAtAHundredCharacters() {
        #expect(UploadForm.titleLimit == 100)
        #expect(UploadForm.title(String(repeating: "a", count: 100)).count == 100)
        #expect(UploadForm.title(String(repeating: "a", count: 101)).count == 100)
        #expect(UploadForm.title(String(repeating: "👩‍👩‍👧", count: 120)).count == 100)
    }

    /// The description's limit is in bytes, and the cut must not fall inside a character.
    @Test func aDescriptionStopsAtFiveThousandBytesOnACharacterBoundary() {
        let ascii = UploadForm.description(String(repeating: "a", count: 6000))
        #expect(ascii.utf8.count == 5000)

        let wide = UploadForm.description(String(repeating: "é", count: 4000))   // 2 bytes each
        #expect(wide.utf8.count == 5000)
        #expect(wide.count == 2500)

        let odd = UploadForm.description("a" + String(repeating: "é", count: 4000))
        #expect(odd.utf8.count == 4999)
        #expect(String(data: Data(odd.utf8), encoding: .utf8) == odd)
    }

    /// A rule that rewrites the field must leave the insertion point where the typing was.
    @Test func theInsertionPointFollowsTheTextBeforeIt() {
        #expect(UploadForm.caret(3, in: "ab<cd", after: UploadForm.title) == 2)
        #expect(UploadForm.caret(5, in: "ab<cd", after: UploadForm.title) == 4)

        let full = String(repeating: "a", count: 100)
        let typedInTheMiddle = String(full.prefix(50)) + "x" + String(full.suffix(50))
        #expect(UploadForm.caret(51, in: typedInTheMiddle, after: UploadForm.title) == 51)
        let pastedPastTheLimit = String(repeating: "a", count: 150)
        #expect(UploadForm.caret(150, in: pastedPastTheLimit, after: UploadForm.title) == 100)

        // Offsets are UTF-16, where an emoji is two.
        #expect(UploadForm.caret(5, in: "😀<😀x", after: UploadForm.title) == 4)
        #expect(UploadForm.caret(99, in: "a<b", after: UploadForm.title) == 2)
        #expect(UploadForm.caret(-1, in: "a<b", after: UploadForm.title) == 0)
        #expect(UploadForm.caret(2, in: "é<é", after: UploadForm.description) == 1)
    }

    @Test func onlyATitleWithSomethingInItCanBeUploaded() {
        #expect(UploadForm.canUpload(title: "A clip"))
        for blank in ["", "   ", "\n\t"] { #expect(!UploadForm.canUpload(title: blank)) }
    }

    @Test func theTitleStartsAsTheRecordingsOwnName() {
        let source = URL(fileURLWithPath: "/tmp/Recording 2026-11-16 at 14.03.22.mov")
        #expect(UploadForm.defaultTitle(for: source) == "Recording 2026-11-16 at 14.03.22")
        #expect(UploadForm.defaultTitle(for: URL(fileURLWithPath: "/tmp/a<b>.mov")) == "ab")
    }

    /// The last line of defence: whatever reached the fields, by typing or otherwise, what is sent
    /// obeys the rules and has a title.
    @Test func whatIsSentIsNormalisedAndNeverUntitled() {
        let sent = UploadForm.metadata(
            title: "  My <clip>  ", description: "  about it\n", privacy: .private,
            fallbackTitle: "Fallback")
        #expect(sent == VideoMetadata(title: "My clip", description: "about it", privacy: .private))

        let blank = UploadForm.metadata(
            title: "  ", description: "", privacy: .unlisted, fallbackTitle: "Fallback")
        #expect(blank.title == "Fallback")
    }

    @Test func onlyAClipPastFifteenMinutesIsLong() {
        #expect(!UploadForm.isLong(seconds: 900))
        #expect(UploadForm.isLong(seconds: 900.5))
    }

    // MARK: - The Trim window's row

    private let profile = "H.264 1920 × 1200"

    private func caption(
        _ account: UploadModel.Account, failure: String? = nil, canSignIn: Bool = true,
        cropped: Bool = false
    ) -> String {
        UploadCopy.trimCaption(
            for: account, failure: failure, canSignIn: canSignIn, profile: profile, cropped: cropped)
    }

    @Test func theButtonDoesWhatTheAccountAllows() {
        #expect(UploadCopy.trimAction(.connected(expires: nil), canSignIn: true) == .upload)
        #expect(UploadCopy.trimAction(.disconnected, canSignIn: true) == .connect)
        #expect(UploadCopy.trimAction(.connecting, canSignIn: true) == .cancelSignIn)
        for dead in [UploadModel.Account.unavailable, .disconnecting] {
            #expect(UploadCopy.trimAction(dead, canSignIn: true) == .none)
        }
        // A sign-in another build saved can be ended here, but not used.
        #expect(UploadCopy.trimAction(.connected(expires: nil), canSignIn: false) == .none)
    }

    /// A sign-in abandoned in the browser would otherwise leave the row dead for five minutes.
    @Test func theButtonIsCancelOnlyWhileSigningIn() {
        #expect(UploadCopy.trimButton(.connecting) == "Cancel")
        for other in [UploadModel.Account.unavailable, .disconnected, .connected(expires: nil), .disconnecting] {
            #expect(UploadCopy.trimButton(other) == "Upload to YouTube…")
        }
    }

    /// The same size line `Export & Copy` quotes, so the two rows describe one file.
    @Test func theCaptionSaysWhatWillBeUploaded() {
        #expect(
            caption(.connected(expires: nil))
                == "Uploads only the range — H.264 1920 × 1200 — to your YouTube channel. Asks for a title first.")
        #expect(caption(.connected(expires: nil), cropped: true).contains("only the range, cropped"))
    }

    @Test func theCaptionFollowsTheAccount() {
        #expect(caption(.disconnected) == "Uploads only the range to YouTube. You'll connect an account first.")
        #expect(caption(.connecting) == "Waiting for Google in your browser…")
        #expect(caption(.unavailable, canSignIn: false) == "This build has no YouTube credentials.")
        #expect(
            caption(.connected(expires: nil), canSignIn: false)
                == "This build has no YouTube credentials, so it can't use the saved sign-in.")
        #expect(caption(.disconnected, failure: "Why not.") == "Why not.")
    }

    // MARK: - The alert and the sheet

    /// Google's pages are translated and worded differently in testing and in production (07), so
    /// the alert describes the warning and never names a button on it.
    @Test func theConnectAlertDescribesGooglesWarningWithoutQuotingIt() {
        let message = UploadCopy.connectMessage
        #expect(message.contains("adding videos to your channel"))
        #expect(message.contains("continue past the warning"))
        for quoted in ["Advanced", "Back to safety", "Go to ScreenRec", "unsafe", "Allow"] {
            #expect(!message.contains(quoted), "\(quoted)")
        }
    }

    @Test func theSheetSaysWhereTheVideoGoes() {
        #expect(
            UploadCopy.sheetDestination(channel: "My channel")
                == "Goes to “My channel”. YouTube's Terms of Service apply.")
        #expect(
            UploadCopy.sheetDestination(channel: nil)
                == "Goes to the channel you connected. YouTube's Terms of Service apply.")
    }

    /// A weight and a size are quoted only once there is geometry to compute them from.
    @Test func theSheetQuotesOnlyWhatItCanCompute() {
        #expect(UploadCopy.sheetSummary(seconds: 24, bytes: nil, profile: nil) == "0:24")
        let full = UploadCopy.sheetSummary(seconds: 24, bytes: 18_000_000, profile: profile)
        #expect(full.hasPrefix("0:24 · up to "))
        #expect(full.hasSuffix(" · H.264 1920 × 1200"))
    }

    @Test func theAccountRowNamesTheChannelOnceItIsKnown() {
        #expect(UploadCopy.status(.connected(expires: nil), channel: "My channel") == "Connected · My channel")
        #expect(UploadCopy.status(.connected(expires: nil), channel: nil) == "Connected")
        #expect(UploadCopy.status(.disconnected, channel: "My channel") == "Not connected")
    }

    // MARK: - The notices

    @Test func aLandedUploadIsAnnouncedWithItsLink() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        let notice = RecordingNotifications.uploaded(
            title: "My clip", visibility: "unlisted", link: "https://youtu.be/abc123XYZ_-", file: file)
        #expect(notice.title == "Uploaded to YouTube")
        #expect(notice.body == "“My clip” is unlisted · youtu.be/abc123XYZ_-. Click to reveal the file.")
        #expect(notice.fileURL == file)
    }

    /// The export always finished first, so a failed upload still names a file that exists.
    @Test func aFailedUploadSaysWhyAndNamesTheFileThatIsSaved() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        let notice = RecordingNotifications.uploadFailed(reason: "The connection dropped.", file: file)
        #expect(notice.title == "Couldn't upload to YouTube")
        #expect(notice.body == "The connection dropped. The clip is saved as Clip trimmed.mp4.")
        #expect(notice.fileURL == file)
    }

    @Test func eachFailureHasItsReason() {
        #expect(UploadCopy.uploadFailure(GoogleSignInError.signInExpired) == "YouTube needs reconnecting in Settings.")
        #expect(UploadCopy.uploadFailure(YouTubeError.notAuthorized) == "YouTube needs reconnecting in Settings.")
        #expect(UploadCopy.uploadFailure(UploadModelError.notConnected) == "YouTube isn't connected.")
        #expect(UploadCopy.uploadFailure(YouTubeError.quotaExceeded) == "YouTube's daily upload limit for this build is used up.")
        #expect(UploadCopy.uploadFailure(YouTubeError.noChannel) == "This Google account has no YouTube channel.")
        #expect(UploadCopy.uploadFailure(YouTubeError.uploadLimitExceeded) == "Your channel has reached YouTube's upload limit for today.")
        #expect(UploadCopy.uploadFailure(URLError(.networkConnectionLost)) == "The connection dropped.")
        #expect(
            UploadCopy.uploadFailure(YouTubeError.rejected(status: 400, reason: "invalidTitle", message: nil))
                == "YouTube refused the upload.")
    }

    /// A reason that names YouTube has to be YouTube's: a file that went missing isn't.
    @Test func aFailureOnThisMacDoesNotBlameYouTube() {
        #expect(UploadCopy.uploadFailure(YouTubeError.unreadableFile) == "The exported file couldn't be read.")
        #expect(UploadCopy.uploadFailure(CocoaError(.fileReadNoPermission)) == "The upload didn't finish.")
        #expect(UploadCopy.uploadFailure(YouTubeError.malformedResponse) == "The upload didn't finish.")
    }
}
