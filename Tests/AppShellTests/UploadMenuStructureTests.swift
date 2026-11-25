import AppKit
import Foundation
import Testing
import UploadCore

@testable import AppCore
@testable import AppShell

/// The upload's rows in the real menu (M40-T4): the progress row and `Cancel Upload`, the receipt
/// and its links, and `Upload to YouTube…` on the files that can take it.
@MainActor
@Suite struct UploadMenuStructureTests {

    private let metadata = VideoMetadata(title: "My clip", description: "", privacy: .unlisted)
    private let video = UploadedVideo(
        id: "abc123XYZ_-", title: "My clip", privacyStatus: "unlisted", uploadStatus: "uploaded",
        channelTitle: "My channel")

    private func state(
        credentials: Bool = true, connected: Bool = true, directory: URL? = nil
    ) -> AppState {
        let token = GoogleToken(
            accessToken: "at", accessTokenExpiry: Date().addingTimeInterval(3000), refreshToken: "rt")
        let uploads = UploadModel(
            credentials: credentials
                ? GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret") : nil,
            store: connected ? InMemoryTokenStore(token) : InMemoryTokenStore())
        let state = AppState(defaults: TestSuites.make(), uploads: uploads)
        if let directory { state.outputDirectory = directory }
        return state
    }

    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-row-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 1000).write(to: url)
        return url
    }

    private func drain(_ uploads: UploadModel) async {
        while uploads.uploadInProgress != nil || uploads.queuedUploadCount > 0 {
            await uploads.uploadTask?.value
        }
    }

    private func submenu(_ state: AppState, of title: String) -> [String] {
        (MenuSnapshot.item(state, titled: title)?.submenu?.items ?? [])
            .map { $0.isSeparatorItem ? "---" : $0.title }
    }

    // MARK: - While it runs

    @Test func anUploadInFlightShowsItsProgressAndAWayToStopIt() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = state()
        let idle = MenuSnapshot.titles(state)
        let finish = AsyncStream<Void>.makeStream()
        state.uploads.uploadFunction = { [video] _, _, _, _ in
            for await _ in finish.stream { break }
            return video
        }

        state.uploads.upload(file, metadata: metadata)
        let titles = MenuSnapshot.titles(state)
        let at = try #require(titles.firstIndex(of: "Uploading to YouTube… 0%"))
        #expect(Array(titles[at...(at + 2)]) == ["Uploading to YouTube… 0%", "Cancel Upload", "---"])
        // In the receipt group, under Start and Arm — never above them (docs/06, M12-T3).
        #expect(Array(titles[..<at]) == Array(idle[..<at]))
        #expect(titles.count == idle.count + 3)

        let row = MenuSnapshot.item(state, titled: "Uploading to YouTube… 0%")
        #expect((row?.view as? ProgressRowView)?.kind == .upload)
        #expect(row?.isEnabled == false)
        #expect(MenuSnapshot.item(state, titled: "Cancel Upload")?.isEnabled == true)

        state.uploads.upload(file, metadata: metadata)
        #expect(MenuSnapshot.titles(state).contains("Uploading to YouTube… 0% · 1 waiting"))

        finish.continuation.yield()
        finish.continuation.yield()
        await drain(state.uploads)
        #expect(!MenuSnapshot.titles(state).contains("Cancel Upload"))
    }

    /// A transfer that broke and is waiting to be picked up says so on its row, drawn and read
    /// alike — a percentage that has stopped is otherwise a mystery (M40-T5).
    @Test func aStalledUploadSaysItIsWaitingForTheConnection() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = state()
        let finish = AsyncStream<Void>.makeStream()
        state.uploads.uploadFunction = { [video] _, _, pass, _ in
            pass.waiting(true)
            for await _ in finish.stream { break }
            return video
        }

        state.uploads.upload(file, metadata: metadata)
        for _ in 0..<2000 where !state.uploads.uploadIsWaiting { await Task.yield() }
        let title = "Uploading to YouTube… 0% · waiting for the connection"
        #expect(MenuSnapshot.titles(state).contains(title))
        let view = MenuSnapshot.item(state, titled: title)?.view as? ProgressRowView
        #expect(view?.note == "· waiting for the connection")
        #expect(MenuSnapshot.item(state, titled: "Cancel Upload")?.isEnabled == true)

        finish.continuation.yield()
        await drain(state.uploads)
    }

    /// The export's bar and the upload's are the same view: each is told apart by its kind, so a
    /// tick meant for one is never drawn on the other.
    @Test func theExportRowKeepsItsOwnKind() {
        #expect(ProgressRowView(fraction: 0.5).kind == .export)
        #expect(
            ProgressRowView(.upload, lead: MenuHeader.uploadingLead, fraction: 0.5).kind
                == .upload)
    }

    /// The first upload's notice may have sent the user to the menu for its link, so its receipt
    /// stays up while the next one runs — above it, in the order things happened.
    @Test func theLastReceiptStaysUpWhileAnotherUploadRuns() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = state()
        state.uploads.uploadFunction = { [video] _, _, _, _ in video }
        state.uploads.upload(file, metadata: metadata)
        await drain(state.uploads)

        let finish = AsyncStream<Void>.makeStream()
        state.uploads.uploadFunction = { [video] _, _, _, _ in
            for await _ in finish.stream { break }
            return video
        }
        state.uploads.upload(file, metadata: metadata)

        let titles = MenuSnapshot.titles(state)
        let receipt = try #require(titles.firstIndex(of: "Uploaded to YouTube · My clip"))
        #expect(Array(titles[receipt...(receipt + 4)]) == [
            "Uploaded to YouTube · My clip", "---",
            "Uploading to YouTube… 0%", "Cancel Upload", "---",
        ])

        finish.continuation.yield()
        await drain(state.uploads)
    }

    /// Rows are stamped at open. If the upload under `Cancel Upload` lands and the next begins
    /// while the menu is still up, pressing the row must not stop the one it never showed.
    @Test func aCancelRowStopsOnlyTheUploadItWasBuiltFor() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = state()
        let started = Started()
        let first = AsyncStream<Void>.makeStream()
        let second = AsyncStream<Void>.makeStream()
        state.uploads.uploadFunction = { [video] _, _, _, _ in
            let stream = started.next() == 1 ? first.stream : second.stream
            for await _ in stream { break }
            // As a real transfer does: a cancelled one throws rather than landing.
            try Task.checkCancellation()
            return video
        }
        let landed = Started()
        state.notifier = { if $0.title.hasPrefix("Uploaded to YouTube") { _ = landed.next() } }
        state.uploads.upload(file, metadata: metadata)
        state.uploads.upload(file, metadata: metadata)
        let cancel = try #require(MenuSnapshot.item(state, titled: "Cancel Upload"))

        first.continuation.yield()
        for _ in 0..<2000 where started.count < 2 { await Task.yield() }
        try #require(started.count == 2)
        _ = cancel.target?.perform(cancel.action)

        second.continuation.yield()
        await drain(state.uploads)
        #expect(landed.count == 2)   // the second went up: the stale row did not stop it
    }

    // MARK: - A failed upload (M40-T6)

    private let session = UploadSession(
        url: URL(string: "https://upload.example/session-1")!, fileSize: 1000, contentType: "video/mp4")

    @Test func aFailedUploadStaysInTheMenuWithAWayToTryAgain() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = state()
        let attempts = Started()
        state.uploads.uploadFunction = { [video, session] _, _, pass, _ in
            guard attempts.next() == 1 else { return video }
            pass.opened(session)
            throw UploadGaveUp(underlying: URLError(.networkConnectionLost))
        }
        state.uploads.upload(file, metadata: metadata)
        await drain(state.uploads)

        let row = "Couldn't upload · My clip"
        #expect(MenuSnapshot.titles(state).contains(row))
        #expect(submenu(state, of: row) == [
            "The connection dropped and didn't come back in 5 minutes.", "---",
            "Try Again", "Reveal File in Finder", "Open YouTube Studio", "---",
            "Dismiss",
        ])
        let items = MenuSnapshot.item(state, titled: row)?.submenu?.items ?? []
        #expect(items.first?.isEnabled == false)             // the reason states; it does nothing
        #expect(
            MenuSnapshot.item(state, titled: "Open YouTube Studio")?.representedObject as? URL
                == URL(string: "https://studio.youtube.com"))

        let tryAgain = try #require(MenuSnapshot.item(state, titled: "Try Again"))
        #expect(tryAgain.isEnabled)
        _ = tryAgain.target?.perform(tryAgain.action)
        await drain(state.uploads)
        #expect(!MenuSnapshot.titles(state).contains(row))
        #expect(MenuSnapshot.titles(state).contains("Uploaded to YouTube · My clip"))
        #expect(attempts.count == 2)
    }

    /// The row is the upload, not a snapshot of it: a clip renamed after the menu was built
    /// must not turn its `Try Again` into a press that does nothing.
    @Test func tryAgainStillWorksOnARowBuiltBeforeItsClipWasRenamed() async throws {
        let file = try makeFile()
        let renamed = file.deletingLastPathComponent()
            .appendingPathComponent("renamed-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: renamed)
        }
        let state = state()
        let attempts = Started()
        state.uploads.uploadFunction = { [video] _, _, _, _ in
            guard attempts.next() == 1 else { return video }
            throw YouTubeError.uploadLimitExceeded
        }
        state.uploads.upload(file, metadata: metadata)
        await drain(state.uploads)
        let tryAgain = try #require(MenuSnapshot.item(state, titled: "Try Again"))

        try FileManager.default.moveItem(at: file, to: renamed)
        state.uploads.fileRenamed(from: file, to: renamed)
        _ = tryAgain.target?.perform(tryAgain.action)
        await drain(state.uploads)

        #expect(attempts.count == 2)
        #expect(state.uploads.lastUpload?.file == renamed)
    }

    /// Nothing to try and nothing to open: the reason, and the way to clear it.
    @Test func aFailureWithNothingToRetryOffersOnlyItsReasonAndDismiss() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString).mp4")
        let state = state()
        state.uploads.upload(missing, metadata: metadata)
        await drain(state.uploads)

        let row = "Couldn't upload · My clip"
        #expect(submenu(state, of: row) == [
            "The clip was moved or deleted before it could be sent.", "---", "Dismiss",
        ])
        let dismiss = try #require(MenuSnapshot.item(state, titled: "Dismiss"))
        _ = dismiss.target?.perform(dismiss.action)
        #expect(!MenuSnapshot.titles(state).contains(row))
    }

    /// Between the receipt and the upload running now: landed, failed, in flight.
    @Test func theFailedRowSitsBetweenTheReceiptAndTheRunningUpload() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let state = state()
        state.uploads.uploadFunction = { [video] _, _, _, _ in video }
        state.uploads.upload(file, metadata: metadata)
        await drain(state.uploads)
        state.uploads.uploadFunction = { _, _, _, _ in throw YouTubeError.uploadLimitExceeded }
        state.uploads.upload(file, metadata: VideoMetadata(title: "Second", privacy: .unlisted))
        await drain(state.uploads)
        let finish = AsyncStream<Void>.makeStream()
        state.uploads.uploadFunction = { [video] _, _, _, _ in
            for await _ in finish.stream { break }
            return video
        }
        state.uploads.upload(file, metadata: VideoMetadata(title: "Third", privacy: .unlisted))

        let titles = MenuSnapshot.titles(state)
        let receipt = try #require(titles.firstIndex(of: "Uploaded to YouTube · My clip"))
        #expect(Array(titles[receipt...(receipt + 6)]) == [
            "Uploaded to YouTube · My clip", "---",
            "Couldn't upload · Second", "---",
            "Uploading to YouTube… 0%", "Cancel Upload", "---",
        ])
        // No account trouble, nothing opened: the retry is offered, and there is no entry to open.
        #expect(submenu(state, of: "Couldn't upload · Second") == [
            "Your channel has reached YouTube's upload limit for today.", "---",
            "Try Again", "Reveal File in Finder", "---", "Dismiss",
        ])

        finish.continuation.yield()
        await drain(state.uploads)
    }

    // MARK: - The receipt

    @Test func aLandedUploadLeavesAReceiptWithItsLinkThreeWays() async throws {
        let file = try makeFile()
        let state = state()
        state.uploads.uploadFunction = { [video] _, _, _, _ in video }
        state.uploads.upload(file, metadata: metadata)
        await drain(state.uploads)

        let receipt = "Uploaded to YouTube · My clip"
        #expect(MenuSnapshot.titles(state).contains(receipt))
        #expect(submenu(state, of: receipt) == [
            "Copy Link", "Open on YouTube", "Edit in YouTube Studio", "---",
            "Reveal File in Finder",
        ])
        #expect(
            MenuSnapshot.item(state, titled: "Open on YouTube")?.representedObject as? URL
                == URL(string: "https://youtu.be/abc123XYZ_-"))
        #expect(
            MenuSnapshot.item(state, titled: "Edit in YouTube Studio")?.representedObject as? URL
                == URL(string: "https://studio.youtube.com/video/abc123XYZ_-/edit"))

        // The clip has gone; the link has not.
        try FileManager.default.removeItem(at: file)
        #expect(submenu(state, of: receipt) == [
            "Copy Link", "Open on YouTube", "Edit in YouTube Studio",
        ])
    }

    // MARK: - The per-file row

    @Test func anExportedMP4CanBeUploadedFromItsRowAndNothingElseCan() throws {
        let directory = try MenuSnapshot.directory([
            ("a trimmed.mp4", 0), ("b.mov", 0), ("c.gif", 0),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = state(directory: directory)
        state.refreshRecentRecordings()

        #expect(submenu(state, of: "a trimmed.mp4").filter { $0 != "---" } == [
            "Reveal in Finder", "Play", "Share…", "Copy", "Upload to YouTube…",
            "Save as GIF", "Export Audio", "Trim…",
            "Rename…", "Move to Trash",
        ])
        #expect(!submenu(state, of: "b.mov").contains("Upload to YouTube…"))
        #expect(!submenu(state, of: "c.gif").contains("Upload to YouTube…"))
    }

    @Test func theRowIsAbsentWithoutCredentialsAndOfferedBeforeAnAccountExists() throws {
        let directory = try MenuSnapshot.directory([("a trimmed.mp4", 0)])
        defer { try? FileManager.default.removeItem(at: directory) }

        let unavailable = state(credentials: false, connected: false, directory: directory)
        unavailable.refreshRecentRecordings()
        #expect(!submenu(unavailable, of: "a trimmed.mp4").contains("Upload to YouTube…"))

        // Pressing it with no account is how one gets connected, so the row is live.
        let disconnected = state(connected: false, directory: directory)
        disconnected.refreshRecentRecordings()
        #expect(disconnected.uploads.account == .disconnected)
        #expect(MenuSnapshot.item(disconnected, titled: "Upload to YouTube…")?.isEnabled == true)
    }

    @Test func theRowWaitsWhileASignInIsInTheBrowser() async throws {
        let directory = try MenuSnapshot.directory([("a trimmed.mp4", 0)])
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = state(connected: false, directory: directory)
        state.refreshRecentRecordings()
        state.uploads.signIn = { _, _ in
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }

        state.uploads.connect()
        #expect(state.uploads.account == .connecting)
        #expect(MenuSnapshot.item(state, titled: "Upload to YouTube…")?.isEnabled == false)

        state.uploads.cancelConnect()
        await state.uploads.connectTask?.value
        #expect(MenuSnapshot.item(state, titled: "Upload to YouTube…")?.isEnabled == true)
    }
}

/// Counts the fake uploader's calls across threads.
private final class Started: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func next() -> Int { lock.withLock { calls += 1; return calls } }
    var count: Int { lock.withLock { calls } }
}
