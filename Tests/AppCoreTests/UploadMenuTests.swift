import Foundation
import RecorderCore
import Testing
import UploadCore

@testable import AppCore

/// What the menu, the notice and a quit are told about an upload (M40-T4): the row's words, the
/// receipt, the clipboard rule, cancelling, and what is still outstanding.
@MainActor
@Suite struct UploadMenuTests {

    private let credentials = GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret")
    private let metadata = VideoMetadata(title: "My clip", description: "", privacy: .unlisted)
    private let link = "https://youtu.be/abc123XYZ_-"

    private func token() -> GoogleToken {
        GoogleToken(
            accessToken: "at", accessTokenExpiry: Date().addingTimeInterval(3000), refreshToken: "rt")
    }

    private func video(_ id: String = "abc123XYZ_-", title: String? = "My clip") -> UploadedVideo {
        UploadedVideo(
            id: id, title: title, privacyStatus: "unlisted", uploadStatus: "uploaded",
            channelTitle: "My channel")
    }

    private func makeFile(_ name: String = "clip") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-menu-\(name)-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 1000).write(to: url)
        return url
    }

    private func makeModel(defaults: UserDefaults? = nil) -> (model: UploadModel, posted: Posted) {
        let model = UploadModel(
            credentials: credentials, store: InMemoryTokenStore(token()), defaults: defaults)
        let posted = Posted()
        model.notify = { posted.append($0) }
        return (model, posted)
    }

    private func makeState() -> AppState {
        AppState(
            defaults: TestDefaults.make(),
            uploads: UploadModel(credentials: credentials, store: InMemoryTokenStore(token())))
    }

    private func drain(_ model: UploadModel) async {
        while model.uploadInProgress != nil || model.queuedUploadCount > 0 {
            await model.uploadTask?.value
        }
    }

    /// A clipboard that counts its changes, as the pasteboard does.
    private final class Clipboard: @unchecked Sendable {
        var changeCount = 7
        var text: String?

        @MainActor func wire(_ model: UploadModel) {
            model.clipboardChangeCount = { self.changeCount }
            model.copyToClipboard = {
                self.text = $0
                self.changeCount += 1
            }
        }
    }

    // MARK: - The row's words

    @Test func theRowSaysHowFarTheUploadIs() {
        #expect(MenuHeader.uploading(fraction: 0) == "Uploading to YouTube… 0%")
        #expect(MenuHeader.uploading(fraction: 0.374) == "Uploading to YouTube… 37%")
        #expect(MenuHeader.uploading(fraction: 1) == "Uploading to YouTube… 100%")
        #expect(MenuHeader.uploading(fraction: 1.4) == "Uploading to YouTube… 100%")
        #expect(
            MenuHeader.uploading(fraction: 0.374, waiting: 2) == "Uploading to YouTube… 37% · 2 waiting")
        #expect(MenuHeader.waitingNote(0) == nil)
        #expect(MenuHeader.waitingNote(1) == "· 1 waiting")
    }

    // MARK: - The receipt

    @Test func theReceiptIsNamedByTheVideoAndCarriesItsLinks() {
        let upload = LastUpload(
            videoID: "abc123XYZ_-", title: "My clip", file: URL(fileURLWithPath: "/tmp/Clip.mp4"),
            date: Date())
        #expect(upload.menuTitle == "Uploaded to YouTube · My clip")
        #expect(upload.link == link)
        #expect(upload.watchURL == URL(string: link))
        #expect(
            upload.studioURL == URL(string: "https://studio.youtube.com/video/abc123XYZ_-/edit"))
    }

    /// A menu is as wide as its widest row, and a title may run to 100 characters.
    @Test func aLongTitleIsCutSoTheMenuStaysNarrow() {
        func receipt(_ title: String) -> String {
            LastUpload(
                videoID: "x", title: title, file: URL(fileURLWithPath: "/tmp/Clip.mp4"), date: Date()
            ).menuTitle
        }
        let forty = String(repeating: "a", count: 40)
        #expect(receipt(forty) == "Uploaded to YouTube · \(forty)")
        #expect(
            receipt(String(repeating: "a", count: 100))
                == "Uploaded to YouTube · \(String(repeating: "a", count: 39))…")
    }

    @Test func aLandedUploadLeavesAReceiptThatSurvivesARelaunch() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        let (model, _) = makeModel(defaults: defaults)
        #expect(model.lastUpload == nil)
        model.uploadFunction = { [video = video()] _, _, _, _ in video }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(model.lastUpload?.videoID == "abc123XYZ_-")
        #expect(model.lastUpload?.title == "My clip")
        #expect(model.lastUpload?.file == file)
        let relaunched = UploadModel(
            credentials: credentials, store: InMemoryTokenStore(token()), defaults: defaults)
        #expect(relaunched.lastUpload == model.lastUpload)
    }

    @Test func theNextUploadReplacesTheReceiptAndAFailedOneLeavesItAlone() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel()
        model.uploadFunction = { [video = video("first", title: "First")] _, _, _, _ in video }
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(model.lastUpload?.videoID == "first")

        model.uploadFunction = { _, _, _, _ in throw URLError(.networkConnectionLost) }
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(model.lastUpload?.videoID == "first")

        model.uploadFunction = { [video = video("second", title: "Second")] _, _, _, _ in video }
        model.upload(file, metadata: metadata)
        await drain(model)
        #expect(model.lastUpload?.videoID == "second")
        #expect(model.lastUpload?.menuTitle == "Uploaded to YouTube · Second")
    }

    /// The export receipt's own hour. The clip going missing is no reason to drop it: the link
    /// still works.
    @Test func theReceiptLastsAnHourWhateverBecomesOfTheClip() async throws {
        let file = try makeFile()
        let defaults = TestDefaults.make()
        let (model, _) = makeModel(defaults: defaults)
        model.uploadFunction = { [video = video()] _, _, _, _ in video }
        model.upload(file, metadata: metadata)
        await drain(model)
        let landed = try #require(model.lastUpload?.date)
        try FileManager.default.removeItem(at: file)

        model.expireStaleReceipt(now: landed.addingTimeInterval(3599))
        #expect(model.lastUpload != nil)

        model.expireStaleReceipt(now: landed.addingTimeInterval(3601))
        #expect(model.lastUpload == nil)
        #expect(SettingsStore.loadLastUpload(from: defaults) == nil)
    }

    @Test func renamingTheClipRepointsTheReceiptAndKeepsItsDate() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel()
        model.uploadFunction = { [video = video()] _, _, _, _ in video }
        model.upload(file, metadata: metadata)
        await drain(model)
        let before = try #require(model.lastUpload)
        let renamed = file.deletingLastPathComponent().appendingPathComponent("Renamed.mp4")

        model.fileRenamed(from: URL(fileURLWithPath: "/tmp/another.mp4"), to: renamed)
        #expect(model.lastUpload == before)

        model.fileRenamed(from: file, to: renamed)
        #expect(model.lastUpload?.file == renamed)
        #expect(model.lastUpload?.date == before.date)
        #expect(model.lastUpload?.videoID == before.videoID)
    }

    /// An upload waiting its turn, or already going up, follows its clip to the new name —
    /// otherwise it would look for a file that has gone, and the receipt would name one.
    @Test func renamingAClipTakesItsQueuedAndRunningUploadsWithIt() async throws {
        let running = try makeFile("running")
        let waiting = try makeFile("waiting")
        let folder = running.deletingLastPathComponent()
        let runningRenamed = folder.appendingPathComponent("running-\(UUID().uuidString).mp4")
        let waitingRenamed = folder.appendingPathComponent("waiting-\(UUID().uuidString).mp4")
        defer {
            for url in [running, waiting, runningRenamed, waitingRenamed] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let (model, _) = makeModel()
        let calls = Calls()
        let started = Gate()
        let finish = Gate()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            if calls.all.count == 1 {
                started.open()
                await finish.wait()
            }
            return video
        }

        model.upload(running, metadata: metadata)
        model.upload(waiting, metadata: metadata)
        await started.reached()
        try FileManager.default.moveItem(at: running, to: runningRenamed)
        model.fileRenamed(from: running, to: runningRenamed)
        try FileManager.default.moveItem(at: waiting, to: waitingRenamed)
        model.fileRenamed(from: waiting, to: waitingRenamed)
        let firstReceipt = Box<URL>()
        model.notify = { if firstReceipt.value == nil { firstReceipt.value = $0.fileURL } }
        finish.open()
        await drain(model)

        #expect(firstReceipt.value == runningRenamed)          // the receipt names where it is now
        #expect(calls.all.map(\.file) == [running, waitingRenamed])   // the queued one was sent from there
        #expect(model.lastUpload?.file == waitingRenamed)
    }

    /// Settings and the Trim window drop a sign-in past its announced end before showing the
    /// account; the menu has to as well, or its row would open a sheet for an upload that can't go.
    @Test func openingTheMenuDropsASignInPastItsEnd() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ending = GoogleToken(
            accessToken: "at", accessTokenExpiry: now.addingTimeInterval(3000), refreshToken: "rt",
            refreshTokenExpiry: now.addingTimeInterval(100))
        let model = UploadModel(credentials: credentials, store: InMemoryTokenStore(ending), now: now)
        #expect(model.account == .connected(expires: now.addingTimeInterval(100)))

        model.prepareForMenu(now: now.addingTimeInterval(50))
        #expect(model.account == .connected(expires: now.addingTimeInterval(100)))

        model.prepareForMenu(now: now.addingTimeInterval(200))
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "The last sign-in has ended. Connect again.")
    }

    // MARK: - The clipboard rule (ADR-024)

    @Test func theLinkIsCopiedWhenTheClipboardIsAsItWas() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let clipboard = Clipboard()
        clipboard.wire(model)
        model.uploadFunction = { [video = video()] _, _, _, _ in video }

        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(clipboard.text == link)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube · link copied"])
    }

    @Test func theLinkStaysInTheMenuWhenTheClipboardChangedMeanwhile() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let clipboard = Clipboard()
        clipboard.wire(model)
        let started = Gate()
        let finish = Gate()
        model.uploadFunction = { [video = video()] _, _, _, _ in
            started.open()
            await finish.wait()
            return video
        }

        model.upload(file, metadata: metadata)
        await started.reached()
        clipboard.changeCount += 1
        finish.open()
        await drain(model)

        #expect(clipboard.text == nil)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
        #expect(model.lastUpload?.link == link)
    }

    /// Two uploads asked for together: the first one's link is itself a change to the clipboard,
    /// so the second does not overwrite it.
    @Test func aSecondLinkDoesNotReplaceTheFirst() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let clipboard = Clipboard()
        clipboard.wire(model)
        let calls = Calls()
        model.uploadFunction = { [first = video("first"), second = video("second")] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            return calls.all.count == 1 ? first : second
        }

        model.upload(file, metadata: metadata)
        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(clipboard.text == "https://youtu.be/first")
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube · link copied", "Uploaded to YouTube"])
    }

    /// From the Trim window the export runs first. The counter is the one read when the sheet was
    /// confirmed, so a copy made during the export counts as a change.
    @Test func theClipboardIsJudgedFromTheSheetNotFromTheEndOfTheExport() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        for changesDuringExport in [false, true] {
            let state = makeState()
            let posted = Posted()
            state.notifier = { posted.append($0) }
            let clipboard = Clipboard()
            clipboard.wire(state.uploads)
            let exporting = Gate()
            let exported = Gate()
            state.exports.exportFunction = { _, _, _, _, _, _ in
                exporting.open()
                await exported.wait()
                return written
            }
            state.uploads.uploadFunction = { [video = video()] _, _, _, _ in video }

            state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
            await exporting.reached()
            if changesDuringExport { clipboard.changeCount += 1 }
            exported.open()
            while state.exports.exportInProgress != nil { await Task.yield() }
            await drain(state.uploads)

            #expect(clipboard.text == (changesDuringExport ? nil : link))
            #expect(
                posted.all.map(\.title)
                    == [changesDuringExport ? "Uploaded to YouTube" : "Uploaded to YouTube · link copied"])
        }
    }

    // MARK: - Cancelling

    @Test func cancellingStopsTheUploadSaysNothingAndStartsTheNext() async throws {
        let first = try makeFile("first")
        let second = try makeFile("second")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let (model, posted) = makeModel()
        let calls = Calls()
        let started = Gate()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            guard calls.all.count == 1 else { return video }
            started.open()
            try await Task.sleep(for: .seconds(60))   // a transfer; cancelling is what ends it
            return video
        }

        model.upload(first, metadata: metadata)
        model.upload(second, metadata: VideoMetadata(title: "Second", privacy: .unlisted))
        await started.reached()
        model.cancelUpload(try #require(model.currentUploadToken))
        await drain(model)

        #expect(calls.all.map(\.file) == [first, second])
        // The fake never reported, so YouTube never heard of the first: nothing to say about it.
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
        #expect(model.lastUpload?.file == second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(model.account == .connected(expires: nil))
    }

    @Test func cancellingWithNothingRunningDoesNothingToTheNextUpload() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        model.uploadFunction = { _, _, _, _ in throw URLError(.networkConnectionLost) }

        #expect(model.currentUploadToken == nil)
        model.cancelUpload(1)   // the token the next upload will have
        model.upload(file, metadata: metadata)
        await drain(model)

        #expect(posted.all.map(\.title) == ["Couldn't upload to YouTube"])
    }

    /// YouTube keeps an unfinished entry for an upload it has opened, which this app's
    /// permission cannot delete — so stopping one after that point says so, once.
    @Test func stoppingAnUploadYouTubeHadOpenedSaysWhatItLeaves() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let started = Gate()
        model.uploadFunction = { [video = video()] _, _, _, progress in
            progress(0)                                   // the session is open
            started.open()
            try await Task.sleep(for: .seconds(60))
            return video
        }

        model.upload(file, metadata: metadata)
        await started.reached()
        #expect(model.stoppedUploadLeavesEntry)
        model.cancelUpload(try #require(model.currentUploadToken))
        #expect(posted.all.map(\.title) == ["Upload to YouTube stopped"])   // said at the press
        await drain(model)

        #expect(posted.all.map(\.title) == ["Upload to YouTube stopped"])
        #expect(posted.all.first?.link == URL(string: "https://studio.youtube.com"))
        #expect(model.lastUpload == nil)
        #expect(!model.stoppedUploadLeavesEntry)
    }

    /// The menu's rows are stamped at open: by the time `Cancel Upload` is pressed, the upload
    /// under it can have landed and the next one begun. The press is for the one it showed.
    @Test func cancelIsForTheUploadItsRowShowed() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let calls = Calls()
        let first = Gate()
        let secondStarted = Gate()
        let second = Gate()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            if calls.all.count == 1 {
                await first.wait()
            } else {
                secondStarted.open()
                await second.wait()
            }
            // As a real transfer does: a cancelled one throws rather than landing.
            try Task.checkCancellation()
            return video
        }

        model.upload(file, metadata: metadata)
        model.upload(file, metadata: metadata)
        let shown = try #require(model.currentUploadToken)
        first.open()
        await secondStarted.reached()

        model.cancelUpload(shown)
        #expect(model.uploadInProgress != nil)
        #expect(model.currentUploadToken != shown)
        second.open()
        await drain(model)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube", "Uploaded to YouTube"])
    }

    /// Quit Anyway: nothing may be left in flight by the time `terminate` asks, and an upload
    /// begun afterwards must not be cleared by the abandoned one's ending.
    @Test func abandoningClearsTheQueueAtOnceAndLeavesALaterUploadAlone() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, posted) = makeModel()
        let calls = Calls()
        let started = Gate()
        let later = Gate()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            if calls.all.count == 1 {
                started.open()
                try await Task.sleep(for: .seconds(60))
            } else {
                await later.wait()
            }
            return video
        }

        model.upload(file, metadata: metadata)
        model.upload(file, metadata: metadata)
        await started.reached()
        #expect(!model.cancelAllUploads())   // nothing had reached YouTube: nothing announced
        #expect(model.uploadInProgress == nil)
        // Required, not expected: with something still queued the rest of this test would wait
        // on an upload nobody opens.
        try #require(model.outstandingUploadCount == 0)

        model.upload(file, metadata: VideoMetadata(title: "Later", privacy: .unlisted))
        for _ in 0..<200 where calls.all.count < 2 { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
        #expect(model.uploadInProgress == "Later")
        #expect(posted.all.isEmpty)

        later.open()
        await drain(model)
        #expect(calls.all.count == 2)
        #expect(posted.all.map(\.title) == ["Uploaded to YouTube"])
    }

    @Test func waitingCoversEveryUploadNotJustTheOneRunning() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let (model, _) = makeModel()
        let calls = Calls()
        let first = Gate()
        let second = Gate()
        model.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            await (calls.all.count == 1 ? first : second).wait()
            return video
        }
        await model.waitForUploadsToFinish()   // nothing in flight: returns at once

        model.upload(file, metadata: metadata)
        model.upload(file, metadata: metadata)
        #expect(model.outstandingUploadCount == 2)
        let done = Flag()
        let waiting = Task {
            await model.waitForUploadsToFinish()
            done.raise()
        }
        first.open()
        for _ in 0..<200 where calls.all.count < 2 { await Task.yield() }
        #expect(!done.isRaised)

        second.open()
        await waiting.value
        #expect(model.outstandingUploadCount == 0)
    }

    // MARK: - Quitting (docs/06 item 12)

    @Test func theQuitQuestionHasAFormForEachKindOfWork() throws {
        #expect(QuitQuestion(exports: 0, uploads: 0) == nil)

        let export = try #require(QuitQuestion(exports: 1, uploads: 0))
        #expect(export.title == "An export is still running.")
        #expect(export.body == "Quitting now throws it away. The recording it came from is untouched.")
        #expect(export.wait == "Wait for Export")
        let exports = try #require(QuitQuestion(exports: 3, uploads: 0))
        #expect(exports.title == "3 exports are still running.")
        #expect(exports.body == "Quitting now throws them away. The recordings they came from are untouched.")

        let upload = try #require(QuitQuestion(exports: 0, uploads: 1))
        #expect(upload.title == "An upload to YouTube is still running.")
        #expect(upload.body == "Quitting now stops it. The clip stays on this Mac.")
        #expect(upload.wait == "Wait for Upload")
        let uploads = try #require(QuitQuestion(exports: 0, uploads: 2))
        #expect(uploads.title == "2 uploads to YouTube are still running.")
        #expect(uploads.body == "Quitting now stops them. The clips stay on this Mac.")

        let both = try #require(QuitQuestion(exports: 1, uploads: 1))
        #expect(both.title == "An export and an upload are still running.")
        #expect(
            both.body
                == "Quitting now throws the export away and stops the upload. The recording is untouched.")
        #expect(both.wait == "Wait for Both")
        #expect(QuitQuestion.quitAnyway == "Quit Anyway")
    }

    /// One export and two uploads is neither all singular nor all plural.
    @Test func aMixedQuitQuestionCountsEachKindOnItsOwn() throws {
        let moreExports = try #require(QuitQuestion(exports: 2, uploads: 1))
        #expect(moreExports.title == "2 exports and an upload are still running.")
        #expect(
            moreExports.body
                == "Quitting now throws the exports away and stops the upload. The recordings are untouched.")

        let moreUploads = try #require(QuitQuestion(exports: 1, uploads: 2))
        #expect(moreUploads.title == "An export and 2 uploads are still running.")
        #expect(
            moreUploads.body
                == "Quitting now throws the export away and stops the uploads. The recording is untouched.")
        #expect(moreUploads.wait == "Wait for Both")
    }

    /// Said before the choice: once the upload is stopped, this app cannot remove what YouTube kept.
    @Test func theQuitQuestionSaysWhenYouTubeWillKeepAnUnfinishedEntry() throws {
        let entry = "YouTube keeps an unfinished entry for the upload already under way; you can delete it in YouTube Studio."
        #expect(
            QuitQuestion(exports: 0, uploads: 1, leavesEntry: true)?.body
                == "Quitting now stops it. The clip stays on this Mac. \(entry)")
        #expect(
            QuitQuestion(exports: 1, uploads: 1, leavesEntry: true)?.body
                == "Quitting now throws the export away and stops the upload. The recording is untouched. \(entry)")
        // An export alone leaves nothing on YouTube, whatever the flag says.
        #expect(
            QuitQuestion(exports: 1, uploads: 0, leavesEntry: true)?.body
                == "Quitting now throws it away. The recording it came from is untouched.")

        #expect(
            QuitQuestion.stopRecordingBody(uploads: 0, leavesEntry: false)
                == "Your recording will be saved first.")
        #expect(
            QuitQuestion.stopRecordingBody(uploads: 1, leavesEntry: false)
                == "Your recording will be saved first. The upload to YouTube is stopped.")
        #expect(
            QuitQuestion.stopRecordingBody(uploads: 2, leavesEntry: true)
                == "Your recording will be saved first. The uploads to YouTube are stopped. \(entry)")
    }

    /// The upload an export will start has not begun, and a quit would lose it all the same.
    @Test func anExportThatWillBeUploadedIsAskedAboutAsBoth() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        let state = makeState()
        #expect(state.quitQuestion == nil)
        #expect(!state.hasExportOrUploadInFlight)
        let exported = Gate()
        state.exports.exportFunction = { _, _, _, _, _, _ in
            await exported.wait()
            return written
        }
        let uploading = Gate()
        let uploaded = Gate()
        state.uploads.uploadFunction = { [video = video()] _, _, _, _ in
            uploading.open()
            await uploaded.wait()
            return video
        }

        state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
        #expect(state.exports.followUpCount == 1)
        #expect(state.quitQuestion?.title == "An export and an upload are still running.")

        exported.open()
        await uploading.reached()
        #expect(state.exports.followUpCount == 0)
        #expect(state.quitQuestion?.title == "An upload to YouTube is still running.")
        #expect(state.hasExportOrUploadInFlight)

        uploaded.open()
        await drain(state.uploads)
        #expect(state.quitQuestion == nil)
    }

    @Test func anExportNobodyIsWaitingToUploadIsOnlyAnExport() async {
        let state = makeState()
        let exported = Gate()
        state.exports.exportFunction = { _, output, _, _, _, _ in
            await exported.wait()
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exports.followUpCount == 0)
        #expect(state.quitQuestion?.title == "An export is still running.")

        exported.open()
        await state.exports.waitForExportToFinish()
    }

    @Test func waitingToQuitLastsThroughAnUploadTheExportHasYetToStart() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        let state = makeState()
        let exported = Gate()
        state.exports.exportFunction = { _, _, _, _, _, _ in
            await exported.wait()
            return written
        }
        let uploading = Gate()
        let uploaded = Gate()
        state.uploads.uploadFunction = { [video = video()] _, _, _, _ in
            uploading.open()
            await uploaded.wait()
            return video
        }

        state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
        let settled = Flag()
        let waiting = Task {
            await state.finishWorkInFlight()
            settled.raise()
        }
        exported.open()
        await uploading.reached()
        for _ in 0..<50 { await Task.yield() }
        #expect(!settled.isRaised)

        uploaded.open()
        await waiting.value
        #expect(state.uploads.lastUpload != nil)
    }

    @Test func quittingAnywayLeavesNothingInFlight() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        let state = makeState()
        let uploading = Gate()
        state.uploads.uploadFunction = { [video = video()] _, _, _, _ in
            uploading.open()
            try await Task.sleep(for: .seconds(60))
            return video
        }
        state.exports.exportFunction = { _, _, _, _, _, _ in
            try await Task.sleep(for: .seconds(60))
            return written
        }

        state.uploadFile(written, metadata: metadata)
        state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
        await uploading.reached()
        #expect(state.quitQuestion?.title == "An export and 2 uploads are still running.")
        #expect(state.stopRecordingQuitBody == "Your recording will be saved first. The uploads to YouTube are stopped.")

        #expect(!state.abandonExportsAndUploads())   // the fake never reported: nothing to announce
        #expect(!state.hasExportOrUploadInFlight)
        #expect(state.quitQuestion == nil)
    }

    /// `Quit Anyway` on an upload YouTube has opened: the notice is posted before the quit, not
    /// from a task that would never get to run.
    @Test func quittingAnywaySaysAtOnceWhatAStoppedUploadLeaves() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = makeState()
        let posted = Posted()
        state.notifier = { posted.append($0) }
        let uploading = Gate()
        state.uploads.uploadFunction = { [video = video()] _, _, _, progress in
            progress(0)
            uploading.open()
            try await Task.sleep(for: .seconds(60))
            return video
        }

        state.uploadFile(file, metadata: metadata)
        await uploading.reached()
        #expect(state.quitQuestion?.body.hasSuffix("you can delete it in YouTube Studio.") == true)

        #expect(state.abandonExportsAndUploads())
        #expect(posted.all.map(\.title) == ["Upload to YouTube stopped"])
    }

    /// `Stop & Quit`, a logout, a shutdown: the recording and the exports are finished, but an
    /// upload is abandoned — a transfer can outlast any quit — and an export on its way out
    /// starts no new one.
    @Test func aQuitNobodyChoseToWaitThroughAbandonsUploadsAndFinishesExports() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        let state = makeState()
        let posted = Posted()
        state.notifier = { posted.append($0) }
        let calls = Calls()
        let uploading = Gate()
        state.uploads.uploadFunction = { [video = video()] file, metadata, accessToken, progress in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            progress(0)
            uploading.open()
            try await Task.sleep(for: .seconds(60))
            return video
        }
        let exported = Gate()
        state.exports.exportFunction = { _, _, _, _, _, _ in
            await exported.wait()
            return written
        }

        state.uploadFile(written, metadata: metadata)
        state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
        await uploading.reached()
        let announced = Box<Bool>()
        let quitting = Task { announced.value = await state.finishWorkBeforeQuitting() }
        for _ in 0..<50 { await Task.yield() }
        #expect(state.uploads.outstandingUploadCount == 0)     // abandoned at once
        #expect(state.exports.exportInProgress != nil)         // the export is still waited for

        exported.open()
        await quitting.value
        #expect(announced.value == true)
        #expect(state.exports.lastExport?.url == written)      // the export finished and is kept
        #expect(calls.all.count == 1)                          // and started no upload of its own
        #expect(state.uploads.outstandingUploadCount == 0)
        #expect(posted.all.map(\.title) == ["Upload to YouTube stopped"])

        state.uploadFile(written, metadata: metadata)          // nothing more is taken
        #expect(state.uploads.outstandingUploadCount == 0)
    }

    /// `Quit Anyway` cancels an export, but a transcode can still come back with a file. Nothing
    /// may follow from it: least of all an upload nobody is there to see.
    @Test func anExportAbandonedByAQuitHandsNothingOn() async throws {
        let written = try makeFile()
        defer { try? FileManager.default.removeItem(at: written) }
        let state = makeState()
        let calls = Calls()
        state.uploads.uploadFunction = { [video = video()] file, metadata, accessToken, _ in
            calls.record(file: file, metadata: metadata, accessToken: accessToken)
            return video
        }
        let exporting = Gate()
        let returned = Gate()
        state.exports.exportFunction = { _, _, _, _, _, _ in
            exporting.open()
            try? await Task.sleep(for: .seconds(60))   // ends when cancelled — and returns anyway
            returned.open()
            return written
        }

        state.uploadClip(URL(fileURLWithPath: "/tmp/Clip.mov"), metadata: metadata)
        await exporting.reached()
        state.exports.cancelExport()                   // the export's half of Quit Anyway
        await returned.reached()
        for _ in 0..<200 { await Task.yield() }

        #expect(calls.all.isEmpty)
        #expect(state.uploads.outstandingUploadCount == 0)
        #expect(state.exports.lastExport == nil)
    }

    // MARK: - The per-file row

    @Test func onlyAnExportedMP4CanBeUploadedFromTheMenu() {
        let clip = URL(fileURLWithPath: "/tmp/Clip trimmed.mp4")
        func row(_ file: URL, _ account: UploadModel.Account, canSignIn: Bool = true) -> UploadCopy.MenuUpload {
            UploadCopy.menuUpload(for: file, account: account, canSignIn: canSignIn)
        }
        #expect(row(clip, .connected(expires: nil)) == .enabled)
        #expect(row(clip, .disconnected) == .enabled)
        #expect(row(clip, .connecting) == .disabled)
        #expect(row(clip, .disconnecting) == .disabled)
        #expect(row(clip, .unavailable, canSignIn: false) == .absent)
        #expect(row(clip, .connected(expires: nil), canSignIn: false) == .absent)
        #expect(row(URL(fileURLWithPath: "/tmp/Clip.MP4"), .connected(expires: nil)) == .enabled)
        for other in ["Clip.mov", "Clip.gif", "Clip.m4a", "Clip"] {
            #expect(row(URL(fileURLWithPath: "/tmp/\(other)"), .connected(expires: nil)) == .absent)
        }
        #expect(UploadCopy.menuUploadTitle == "Upload to YouTube…")
    }

    @Test func anExportedClipsTitleDropsWhatTheExportAdded() {
        func title(_ name: String) -> String {
            UploadForm.defaultTitle(forExport: URL(fileURLWithPath: "/tmp/\(name)"))
        }
        #expect(title("Replay 2026-11-11 at 14.58.55 trimmed.mp4") == "Replay 2026-11-11 at 14.58.55")
        #expect(title("Clip trimmed 2.mp4") == "Clip")
        #expect(title("Clip.mp4") == "Clip")
        #expect(title("Clip 2.mp4") == "Clip 2")
        #expect(title("A trimmed thought.mp4") == "A trimmed thought")
        #expect(title("A<b> trimmed.mp4") == "Ab")
        // Only the export's own ending: a counter is one or two digits, and a year is not one.
        #expect(title("Budget trimmed 2024.mp4") == "Budget trimmed 2024")
        #expect(title("Clip trimmed 99.mp4") == "Clip")
        #expect(title("Clip trimmed 2 extra.mp4") == "Clip trimmed 2 extra")
        #expect(title("Clip trimmedX.mp4") == "Clip trimmedX")
        // And never cut to nothing.
        #expect(title(" trimmed.mp4") == " trimmed")
    }

    @Test func theSheetQuotesAnExistingClipsRealLengthAndWeight() {
        let size = ByteCountFormatter.string(fromByteCount: 33_084_753, countStyle: .file)
        #expect(UploadCopy.fileSummary(seconds: 42, bytes: 33_084_753) == "0:42 · \(size)")
        #expect(UploadCopy.fileSummary(seconds: nil, bytes: 33_084_753) == size)
        #expect(UploadCopy.fileSummary(seconds: 42, bytes: nil) == "0:42")
        #expect(UploadCopy.fileSummary(seconds: nil, bytes: nil).isEmpty)
    }
}
