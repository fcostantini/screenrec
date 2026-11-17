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
    /// YouTube counts a title's 100 in code points (07, measured against the real service): 100
    /// letters and 100 simple emoji pass, 101 letters and 15 family emoji are refused. So that is
    /// what is counted here — and a character made of several is kept whole or not at all.
    @Test func aTitleStopsAtAHundredCodePointsAsYouTubeCountsThem() {
        #expect(UploadForm.titleLimit == 100)
        #expect(UploadForm.title(String(repeating: "a", count: 100)).count == 100)
        #expect(UploadForm.title(String(repeating: "a", count: 101)).count == 100)
        #expect(UploadForm.title(String(repeating: "😀", count: 120)).count == 100)

        let family = "👨‍👩‍👧‍👦"                                  // one character, seven code points
        #expect(family.unicodeScalars.count == 7)
        let kept = UploadForm.title(String(repeating: family, count: 20))
        #expect(kept.count == 14)                            // 98 code points; a fifteenth would be 105
        #expect(kept.unicodeScalars.count == 98)
        #expect(kept == String(repeating: family, count: 14))   // none cut in half

        // 99 letters and one family emoji: the emoji does not fit, and no part of it is kept.
        #expect(UploadForm.title(String(repeating: "a", count: 99) + family) == String(repeating: "a", count: 99))
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

    /// One notice in two forms (ADR-024's clipboard rule), and a click opens the video either way.
    @Test func aLandedUploadSaysWhetherTheLinkWasCopied() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        let link = "https://youtu.be/abc123XYZ_-"
        let copied = RecordingNotifications.uploaded(
            title: "My clip", visibility: "unlisted", link: link, file: file, linkCopied: true)
        #expect(copied.title == "Uploaded to YouTube · link copied")
        #expect(copied.body == "“My clip” is unlisted. ⌘V pastes youtu.be/abc123XYZ_-.")
        #expect(copied.link == URL(string: link))
        #expect(copied.fileURL == file)

        let notice = RecordingNotifications.uploaded(
            title: "My clip", visibility: "unlisted", link: link, file: file, linkCopied: false)
        #expect(notice.title == "Uploaded to YouTube")
        // Spelled out here: the menu's receipt is replaced by the next upload.
        #expect(
            notice.body
                == "“My clip” is unlisted · youtu.be/abc123XYZ_-. Your clipboard changed meanwhile, so the link wasn't copied; it is in the menu under Copy Link.")
        #expect(notice.link == URL(string: link))
        #expect(notice.fileURL == file)
    }

    /// YouTube keeps an entry for an upload it had opened, and this app cannot delete it.
    @Test func aStoppedUploadSaysWhatYouTubeKeepsAndWhereToDeleteIt() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        let notice = RecordingNotifications.uploadStopped(title: "My clip", file: file)
        #expect(notice.title == "Upload to YouTube stopped")
        #expect(
            notice.body
                == "YouTube keeps an unfinished entry named “My clip”. Delete it in YouTube Studio. The clip is saved as Clip trimmed.mp4.")
        #expect(notice.link == URL(string: "https://studio.youtube.com"))
        #expect(notice.fileURL == file)
    }

    /// The reason first, then two sentences that are only said when true.
    @Test func aFailedUploadSaysWhyAndOnlyWhatIsTrueAboutTheClipAndTheEntry() {
        let file = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        func notice(clipExists: Bool, leavesEntry: Bool) -> RecordingNotification {
            RecordingNotifications.uploadFailed(
                reason: "The connection dropped.", title: "My clip", file: file,
                clipExists: clipExists, leavesEntry: leavesEntry)
        }
        let plain = notice(clipExists: true, leavesEntry: false)
        #expect(plain.title == "Couldn't upload to YouTube")
        #expect(plain.body == "The connection dropped. The clip is saved as Clip trimmed.mp4.")
        #expect(plain.fileURL == file)
        #expect(plain.link == nil)

        #expect(
            notice(clipExists: true, leavesEntry: true).body
                == "The connection dropped. The clip is saved as Clip trimmed.mp4. YouTube keeps an unfinished entry named “My clip”; delete it in YouTube Studio.")

        // A clip that has gone is not "saved", and there is nothing to reveal.
        let gone = notice(clipExists: false, leavesEntry: false)
        #expect(gone.body == "The connection dropped.")
        #expect(gone.fileURL == nil)
    }

    /// One sentence per failure, each with its next step and none with a status code.
    @Test func eachFailureHasItsOwnWords() throws {
        let buenosAires = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
        let november = Date(timeIntervalSince1970: 1_794_920_000)   // 17 Nov 2026
        func words(_ failure: UploadFailure) -> String {
            UploadCopy.reason(failure, now: november, timeZone: buenosAires)
        }
        #expect(words(.connectionLost) == "The connection dropped and didn't come back in 5 minutes.")
        #expect(words(.unreachable) == "Couldn't reach YouTube. Check the connection and upload again.")
        #expect(words(.youTubeUnavailable) == "YouTube isn't answering right now. Try again later.")
        #expect(words(.signInEnded) == "YouTube needs reconnecting: the sign-in has ended. Connect again in Settings.")
        #expect(
            words(.signInRefused)
                == "YouTube didn't accept the sign-in. Try again; if it keeps happening, disconnect and connect again in Settings.")
        #expect(words(.notConnected) == "YouTube isn't connected.")
        #expect(words(.channelLimitReached) == "Your channel has reached YouTube's upload limit for today. YouTube lifts it within a day.")
        #expect(words(.projectQuotaSpent) == "This build's YouTube allowance for today is used up. It resets at midnight Pacific (05:00 here).")
        #expect(words(.noChannel) == "This Google account has no YouTube channel. Create one at youtube.com, then upload again.")
        // Two stories behind "nothing uploadable there": gone, or there and unreadable.
        #expect(
            UploadCopy.reason(.clipMissing, clipExists: false)
                == "The clip was moved or deleted before it could be sent.")
        #expect(UploadCopy.reason(.clipMissing, clipExists: true) == "The clip couldn't be read.")
        #expect(words(.refusedTitle) == "YouTube refused the title. Change it and upload again.")
        #expect(words(.refusedDescription) == "YouTube refused the description. Change it and upload again.")
        #expect(words(.refused) == "YouTube refused the upload.")
        #expect(words(.sessionLost) == "YouTube gave up on the unfinished upload. Upload the clip again.")
        #expect(words(.projectNotSetUp) == "This build can't upload: its Google project has the YouTube service switched off.")
        #expect(words(.other) == "The upload didn't finish.")
    }

    /// Google's midnight, said in the Mac's time too — and not twice where they are the same.
    @Test func theAllowanceIsSaidToComeBackAtALocalTime() throws {
        let winter = Date(timeIntervalSince1970: 1_794_920_000)   // 17 Nov 2026: Pacific is UTC−8
        let summer = Date(timeIntervalSince1970: 1_783_000_000)   // 2 Jul 2026: Pacific is UTC−7
        func reset(_ zone: String, _ now: Date) throws -> String {
            UploadCopy.quotaReset(now: now, timeZone: try #require(TimeZone(identifier: zone)))
        }
        #expect(try reset("America/Argentina/Buenos_Aires", winter) == "midnight Pacific (05:00 here)")
        #expect(try reset("America/Argentina/Buenos_Aires", summer) == "midnight Pacific (04:00 here)")
        #expect(try reset("Asia/Tokyo", winter) == "midnight Pacific (17:00 here)")
        #expect(try reset("America/Los_Angeles", winter) == "midnight Pacific")
        #expect(try reset("America/Vancouver", summer) == "midnight Pacific")
    }

    /// The app adds the one failure only it can raise; the rest is the shared list's reading.
    @Test func theAppPlacesItsOwnErrorInTheSharedList() {
        #expect(UploadCopy.failure(for: UploadModelError.notConnected) == .notConnected)
        #expect(UploadCopy.failure(for: YouTubeError.uploadLimitExceeded) == .channelLimitReached)
        #expect(UploadCopy.failure(for: URLError(.timedOut)) == .unreachable)
        #expect(
            UploadCopy.failure(for: UploadGaveUp(underlying: URLError(.timedOut))) == .connectionLost)
        // A failure on this Mac does not blame YouTube.
        #expect(UploadCopy.reason(UploadCopy.failure(for: CocoaError(.fileReadNoPermission))) == "The upload didn't finish.")
    }
}
