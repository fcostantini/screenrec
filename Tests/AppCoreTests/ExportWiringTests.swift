import Foundation
import Testing

@testable import AppCore
import RecorderCore

/// AppState → Exporter wiring, with the transcode injected — the real `Exporter` runs the
/// hardware encoder (that's `ExporterTests`' job), so the wiring is tested on a fake.
@MainActor
@Suite struct ExportWiringTests {

    private func makeState() -> AppState {
        AppState(defaults: TestDefaults.make())
    }

    @Test func exportSetsInProgressSynchronouslyThenReceiptAndNotifies() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let written = URL(fileURLWithPath: "/tmp/Clip.mp4")
        state.exports.exportFunction = { _, _, _, _, _, _ in written }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exports.exportInProgress == "Clip.mov")   // set before the background task runs
        #expect(state.exports.lastExport == nil)

        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(state.exports.lastExport?.url == written)
        #expect(state.exports.lastExport?.menuTitle == "Exported to MP4 · Clip.mp4")
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Exported to MP4")
        #expect(posted.first?.fileURL == written)
    }

    @Test func exportFailureNotifiesAndLeavesNoReceipt() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.exports.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(state.exports.lastExport == nil)
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Couldn't export to MP4")
        #expect(posted.first?.fileURL == nil)
    }

    @Test func aFailedReExportKeepsThePriorReceipt() async {
        let state = makeState()
        state.notifier = { _ in }
        let firstURL = URL(fileURLWithPath: "/tmp/A.mp4")
        state.exports.exportFunction = { _, _, _, _, _, _ in firstURL }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }
        #expect(state.exports.lastExport?.url == firstURL)

        state.exports.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }
        state.exportToMP4(URL(fileURLWithPath: "/tmp/B.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }
        #expect(state.exports.lastExport?.url == firstURL)   // A's pointer isn't erased by B's failure
    }

    /// Was `secondExportWhileOneRunsIsIgnored` until M33-T1: a second request is now queued, so the
    /// assertion moves from "one completed" to "both did, in order".
    /// Bounded drain. `waitForExportToFinish()` is rightly unbounded in production — quitting waits
    /// as long as the work takes — but a stranded queue must **fail** this suite, not hang it
    /// (M15-T1). The break sweep hung on exactly this before the bound existed.
    private func drain(_ state: AppState) async {
        for _ in 0..<10_000 {
            guard state.exports.exportInProgress != nil || state.exports.queuedExportCount > 0
            else { return }
            await Task.yield()
        }
        Issue.record("exports never drained — \(state.exports.queuedExportCount) still queued")
    }

    @Test func secondExportWhileOneRunsIsQueuedNotIgnored() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let ran = Trail()
        state.exports.exportFunction = { source, output, _, _, _, _ in
            ran.append(source.lastPathComponent)
            return output
        }

        // No suspension point between the two calls, so the first export's task hasn't run yet.
        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        state.exportToMP4(URL(fileURLWithPath: "/tmp/B.mov"))
        #expect(state.exports.exportInProgress == "A.mov")
        #expect(state.exports.queuedExportCount == 1)

        await drain(state)
        #expect(ran.items == ["A.mov", "B.mov"])
        #expect(posted.count == 2)
    }

    // MARK: - The fit check (M23-T2)

    /// A real file of known size on a volume the test tells the model is nearly full. The trim path
    /// is used because its estimate is the source's own size, so no media fixture is needed.
    private func makeSizedFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exportroom-\(UUID().uuidString).mov")
        try Data(count: bytes).write(to: url)
        return url
    }

    @Test func anExportThatCannotFitIsRefusedBeforeAnythingRuns() async throws {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let source = try makeSizedFile(bytes: 4096)
        defer { try? FileManager.default.removeItem(at: source) }

        let ran = Box<Bool>()
        state.exports.trimFunction = { _, output, _, _, _, _ in ran.value = true; return output }
        state.exports.availableBytes = { _ in 100 }        // less than the source's 4096

        state.trim(source, from: 0, to: 1, mode: .lossless)
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(ran.value != true)                          // nothing was written
        #expect(state.exports.lastExport == nil)                    // and no receipt claims otherwise
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Not enough room to export")
        #expect(posted.first?.fileURL == nil)
    }

    @Test func anExportThatFitsIsNotRefused() async throws {
        // The negative control: without it the guard above passes just as well by refusing
        // everything, which would break every export in the app.
        let state = makeState()
        let source = try makeSizedFile(bytes: 4096)
        defer { try? FileManager.default.removeItem(at: source) }

        let ran = Box<Bool>()
        state.exports.trimFunction = { _, output, _, _, _, _ in ran.value = true; return output }
        state.exports.availableBytes = { _ in 1_000_000_000 }

        state.trim(source, from: 0, to: 1, mode: .lossless)
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(ran.value == true)
        #expect(state.exports.lastExport != nil)
    }

    @Test func aGifIsNeverRefusedForRoom() async {
        // Deliberately ungated: LZW output size can't be predicted, so a guess would refuse GIFs
        // that fit. Pinned so nobody "fixes" the omission with an invented estimate.
        let state = makeState()
        let written = URL(fileURLWithPath: "/tmp/Clip.gif")
        state.exports.gifExportFunction = { _, _, _ in written }
        state.exports.availableBytes = { _ in 0 }

        state.exportToGIF(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(state.exports.lastExport?.url == written)
    }

    @Test func anUnreadableVolumeDoesNotBlockAnExport() async throws {
        let state = makeState()
        let source = try makeSizedFile(bytes: 4096)
        defer { try? FileManager.default.removeItem(at: source) }

        let ran = Box<Bool>()
        state.exports.trimFunction = { _, output, _, _, _, _ in ran.value = true; return output }
        state.exports.availableBytes = { _ in nil }         // capacity can't be read

        state.trim(source, from: 0, to: 1, mode: .lossless)
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(ran.value == true)
    }

    // MARK: - Quit waits for an export (M23-T2)

    @Test func waitingForAnExportReturnsOnlyAfterItSettles() async {
        let state = makeState()
        let finished = Box<Bool>()
        state.exports.exportFunction = { _, output, _, _, _, _ in
            try await Task.sleep(for: .milliseconds(30))
            finished.value = true
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        await state.exports.waitForExportToFinish()

        // The point of the whole thing: quit can't outrun the work.
        #expect(finished.value == true)
        #expect(state.exports.exportInProgress == nil)
    }

    @Test func abandoningAnExportClearsItBeforeQuitLooksAgain() async {
        // "Quit Anyway" calls `terminate`, which runs `applicationShouldTerminate`, which waits for
        // an export in flight. So the clear has to be visible by the time that check runs — i.e.
        // synchronously — or the button waits like the one beside it and its label is a lie.
        let state = makeState()
        state.exports.exportFunction = { _, output, _, _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exports.exportInProgress == "Clip.mov")
        state.exports.cancelExport()
        #expect(state.exports.exportInProgress == nil)   // no await between the two — that is the point

        await state.exports.waitForExportToFinish()      // and quit's wait is now a no-op
        #expect(state.exports.lastExport == nil)         // an abandoned export leaves no receipt
    }

    @Test func waitingWithNoExportRunningReturnsAtOnce() async {
        let state = makeState()
        await state.exports.waitForExportToFinish()      // must not hang
        #expect(state.exports.exportInProgress == nil)
    }

    @Test func gifExportSetsReceiptAndNotifies() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let written = URL(fileURLWithPath: "/tmp/Clip.gif")
        state.exports.gifExportFunction = { _, _, _ in written }

        state.exportToGIF(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exports.exportInProgress == "Clip.mov")
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(state.exports.lastExport?.url == written)
        #expect(state.exports.lastExport?.menuTitle == "Saved as GIF · Clip.gif")
        #expect(posted.first?.title == "Saved as GIF")
        #expect(posted.first?.fileURL == written)
    }

    @Test func gifExportUsesTheSettingsCaps() async {
        let state = makeState()
        state.notifier = { _ in }
        state.gifFPS = 20
        state.gifWidth = 640
        state.gifMaxSeconds = 15
        let recorded = Box<GifConfiguration>()
        state.exports.gifExportFunction = { _, output, configuration in
            recorded.value = configuration
            return output
        }

        state.exportToGIF(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(recorded.value?.fps == 20)
        #expect(recorded.value?.maxWidth == 640)
        #expect(recorded.value?.maxHeight == 640)   // width caps height too
        #expect(recorded.value?.maxSeconds == 15)
    }

    @Test func mp4ExportUsesTheSettingsSize() async {
        // The Size picker is the only thing steering the export; if it stopped arriving, every
        // clip would silently go back to 1920 wide (M18-T2).
        let state = makeState()
        state.notifier = { _ in }
        state.mp4Width = 2560
        let recorded = Box<ExportConfiguration>()
        state.exports.exportFunction = { _, output, configuration, _, _, _ in
            recorded.value = configuration
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(recorded.value?.maxWidth == 2560)
        // The height ceiling is not a preference: it is what keeps the output inside H.264
        // Level 5.2 (docs/02 §3), so every pick carries it.
        #expect(recorded.value?.maxHeight == 2304)
    }

    @Test func aRangedExportCarriesItsRangeAndTakesTheTrimmedName() async {
        // M21-T1's whole point: the Trim window's in/out reach the exporter, and the output can't
        // be mistaken for an export of the whole take.
        let state = makeState()
        state.notifier = { _ in }
        let recordedRange = Box<ExportRange>()
        let recordedOutput = Box<URL>()
        state.exports.exportFunction = { _, output, _, range, _, _ in
            recordedRange.value = range
            recordedOutput.value = output
            return output
        }

        state.exportToMP4(
            URL(fileURLWithPath: "/tmp/Clip.mov"), range: ExportRange(start: 30, end: 35))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(recordedRange.value == ExportRange(start: 30, end: 35))
        #expect(recordedOutput.value?.lastPathComponent == "Clip trimmed.mp4")
    }

    @Test func theTrimWindowsCopyCarriesBothTheSettingsSizeAndItsRange() async {
        // M24-T1: the adapter's whole job. A dropped range copies the whole take; a dropped
        // configuration silently reverts every clip to the default width (M18-T2).
        let state = makeState()
        state.notifier = { _ in }
        state.mp4Width = 2560
        state.exports.copyToPasteboard = { _ in }
        let recorded = Box<ExportConfiguration>()
        let recordedRange = Box<ExportRange>()
        state.exports.exportFunction = { _, output, configuration, range, _, _ in
            recorded.value = configuration
            recordedRange.value = range
            return output
        }

        state.exportAndCopy(
            URL(fileURLWithPath: "/tmp/Clip.mov"), range: ExportRange(start: 12, end: 34))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(recorded.value?.maxWidth == 2560)
        #expect(recordedRange.value == ExportRange(start: 12, end: 34))
    }

    @Test func aWholeFileExportPassesNoRange() async {
        let state = makeState()
        state.notifier = { _ in }
        let recordedRange = Box<ExportRange>()
        let recordedOutput = Box<URL>()
        state.exports.exportFunction = { _, output, _, range, _, _ in
            recordedRange.value = range
            recordedOutput.value = output
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(recordedRange.value == nil)
        #expect(recordedOutput.value?.lastPathComponent == "Clip.mp4")
    }

    /// M33-T3 removed a **silent** `exportInProgress == nil` guard from `stopAndShare`, and its own
    /// sweep proved re-adding it left the suite green — the path needs an active session, which is
    /// what M34-T1 made reachable. This is the test that break now turns red.
    ///
    /// The session is a real `RecordingSession` that is never started: `stopAndWaitForFinalize`
    /// short-circuits on its nil `consumeTask`, so the tail runs without any capture.
    @Test func stopAndShareQueuesBehindARunningExportRatherThanDroppingIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stopandshare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let take = directory.appendingPathComponent("Take.mov")
        try Data().write(to: take)

        let state = makeState()
        state.notifier = { _ in }
        state.exports.copyToPasteboard = { _ in }
        let release = Box<Bool>()
        state.exports.exportFunction = { _, output, _, _, _, _ in
            while release.value != true { await Task.yield() }
            return output
        }

        // An export already running — the state the removed guard would have refused.
        state.exportToMP4(directory.appendingPathComponent("Earlier.mov"))
        #expect(state.exports.exportInProgress != nil)

        // A finished take to share, and a session still in flight: both are needed to reach the tail.
        state.finishTake((url: take, duration: 5))
        let capture = try RecordingSession(
            configuration: CaptureConfiguration(),
            outputURL: directory.appendingPathComponent("Live.mov"))
        state.session.attach(
            capture, outputURL: directory.appendingPathComponent("Live.mov"),
            microphoneName: nil, appName: nil, region: nil)

        await state.stopAndShare()
        #expect(state.exports.queuedExportCount == 1, "the share was dropped instead of queued")

        release.value = true
        while state.exports.exportInProgress != nil { await Task.yield() }
    }

    /// The guard that must stay: nothing to stop means nothing to share, and no export at all.
    @Test func stopAndShareWithNoSessionExportsNothing() async throws {
        let state = makeState()
        state.notifier = { _ in }
        state.exports.exportFunction = { _, output, _, _, _, _ in output }
        state.finishTake((url: URL(fileURLWithPath: "/tmp/Take.mov"), duration: 5))

        await state.stopAndShare()

        #expect(state.exports.exportInProgress == nil)
        #expect(state.exports.queuedExportCount == 0)
    }

    @Test func stopAndCopyLeavesTheExportOnThePasteboardAndPostsOneNotice() async {
        // M21-T2: one action, one notice — not an export receipt plus a copy.
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let copied = Box<URL>()
        state.exports.copyToPasteboard = { copied.value = $0 }
        state.exports.exportFunction = { _, output, _, _, _, _ in output }

        state.exports.exportAndCopy(
            URL(fileURLWithPath: "/tmp/Take.mov"), configuration: ExportConfiguration())
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(copied.value?.lastPathComponent == "Take.mp4")
        #expect(state.exports.lastExport?.url == copied.value)      // the receipt still points at it
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Copied — ⌘V to paste")
        #expect(posted.first?.fileURL == copied.value)      // …and a click still reveals it
    }

    @Test func afailedStopAndCopyLeavesThePasteboardAlone() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let copied = Box<URL>()
        state.exports.copyToPasteboard = { copied.value = $0 }
        state.exports.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }

        state.exports.exportAndCopy(
            URL(fileURLWithPath: "/tmp/Take.mov"), configuration: ExportConfiguration())
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(copied.value == nil)                        // nothing was copied…
        #expect(posted.first?.title == "Couldn't export to MP4")   // …and nothing claims otherwise
    }

    @Test func withoutAPasteboardTheNoticeDoesNotClaimACopy() async {
        // The app always injects one; a notice that says "Copied" when nothing was is the failure
        // this guards — the export itself is still worth keeping.
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.exports.exportFunction = { _, output, _, _, _, _ in output }

        state.exports.exportAndCopy(
            URL(fileURLWithPath: "/tmp/Take.mov"), configuration: ExportConfiguration())
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(posted.first?.title == "Exported to MP4")
    }

    @Test func theSizePickerStatesWhatEachPickCosts() {
        // Every pick plays anywhere (M18-T2), so weight is what actually decides between them —
        // and "Largest" is a fit, not a number, so the row says what it means for this source.
        let state = makeState()
        state.refreshSources(displays: [DisplayOption(
            id: 1, name: "Built-in", isMain: true,
            pointSize: CGSize(width: 2056, height: 1285), pointPixelScale: 2)])

        #expect(state.mp4SizeLabel(forWidth: 1920) == "1920 px · ≈46 MB per minute")
        #expect(state.mp4SizeLabel(forWidth: 2560) == "2560 px · ≈81 MB per minute")
        let largest = state.mp4SizeLabel(forWidth: Settings.mp4CeilingWidth)
        #expect(largest.hasPrefix("Largest (3686 × 2304) · ≈"))
        #expect(largest.contains("170"))
    }

    @Test func theSizePickerWithholdsAWeightItCannotCompute() {
        // No display geometry ⇒ no fit and no estimate. Never quote a number that can't be
        // computed (M16-T2) — the row degrades to the size alone.
        let state = makeState()
        #expect(state.mp4SizeLabel(forWidth: 1920) == "1920 px")
        #expect(state.mp4SizeLabel(forWidth: Settings.mp4CeilingWidth) == "Largest")
    }

    /// One at a time still holds across formats — it just no longer means the second is lost. The
    /// GIF now runs after the MP4, so the receipt ends up on the *last* one to finish.
    @Test func formatsShareOneQueueAndRunInOrder() async {
        let state = makeState()
        state.notifier = { _ in }
        let ran = Trail()
        state.exports.exportFunction = { _, output, _, _, _, _ in ran.append("mp4"); return output }
        state.exports.gifExportFunction = { _, output, _ in ran.append("gif"); return output }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        state.exportToGIF(URL(fileURLWithPath: "/tmp/A.mov"))
        #expect(state.exports.exportInProgress == "A.mov")
        #expect(state.exports.queuedExportCount == 1)   // the GIF is behind it, not dropped

        await drain(state)
        #expect(ran.items == ["mp4", "gif"])                  // never both at once, and in order
        #expect(state.exports.lastExport?.url.pathExtension == "gif")
    }

    @Test func gifNotificationCopy() {
        let ok = RecordingNotifications.savedAsGIF(url: URL(fileURLWithPath: "/tmp/Clip.gif"))
        #expect(ok.title == "Saved as GIF")
        #expect(ok.body == "Clip.gif — ready to share. Click to reveal.")
        #expect(ok.fileURL == URL(fileURLWithPath: "/tmp/Clip.gif"))

        let failed = RecordingNotifications.gifExportFailed()
        #expect(failed.title == "Couldn't save GIF")
        #expect(failed.fileURL == nil)
    }

    @Test func trimSetsReceiptAndNotifiesWithTheRange() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let written = URL(fileURLWithPath: "/tmp/Clip trimmed.mov")
        let range = Box<(start: Double, end: Double, mode: TrimMode)>()
        state.exports.trimFunction = { _, _, start, end, mode, _ in
            range.value = (start, end, mode)
            return written
        }

        state.trim(URL(fileURLWithPath: "/tmp/Clip.mov"), from: 2, to: 8)
        #expect(state.exports.exportInProgress == "Clip.mov")
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(range.value?.start == 2)
        #expect(range.value?.end == 8)
        #expect(range.value?.mode == .lossless)  // the default stays lossless (ADR-015)
        #expect(state.exports.lastExport?.url == written)
        #expect(state.exports.lastExport?.menuTitle == "Trimmed · Clip trimmed.mov")  // .mov ⇒ "Trimmed"
        #expect(posted.first?.title == "Trimmed")
        #expect(posted.first?.fileURL == written)
    }

    @Test func theTrimWindowsReencodeToggleReachesTheTrim() async {
        // The window's checkbox is the only way to ask for a re-encode; if it stopped arriving,
        // the trim would quietly stay lossless and keep the lead-in it promised to drop (M18-T1).
        let state = makeState()
        let range = Box<(start: Double, end: Double, mode: TrimMode)>()
        state.exports.trimFunction = { _, _, start, end, mode, _ in
            range.value = (start, end, mode)
            return URL(fileURLWithPath: "/tmp/Clip trimmed.mov")
        }

        state.trim(URL(fileURLWithPath: "/tmp/Clip.mov"), from: 2, to: 8, mode: .precise)
        while state.exports.exportInProgress != nil { await Task.yield() }

        #expect(range.value?.mode == .precise)
    }

    @Test func trimNotificationCopy() {
        let ok = RecordingNotifications.trimmed(url: URL(fileURLWithPath: "/tmp/Clip trimmed.mov"))
        #expect(ok.title == "Trimmed")
        #expect(ok.fileURL == URL(fileURLWithPath: "/tmp/Clip trimmed.mov"))
        #expect(RecordingNotifications.trimFailed().title == "Couldn't trim")
        #expect(RecordingNotifications.trimFailed().fileURL == nil)
    }

    @Test func exportNotificationCopy() {
        let ok = RecordingNotifications.exported(url: URL(fileURLWithPath: "/tmp/Clip.mp4"))
        #expect(ok.title == "Exported to MP4")
        #expect(ok.body == "Clip.mp4 — ready to share. Click to reveal.")
        #expect(ok.fileURL == URL(fileURLWithPath: "/tmp/Clip.mp4"))

        let failed = RecordingNotifications.exportFailed()
        #expect(failed.title == "Couldn't export to MP4")
        #expect(failed.fileURL == nil)
    }

    // MARK: - Progress (M28-T4)

    @Test func anMP4ExportIsDeterminateFromTheStartAndClearsWhenDone() async {
        let state = makeState()
        state.notifier = { _ in }
        state.exports.exportFunction = { _, output, _, _, _, _ in output }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exports.exportProgress == 0)   // a bar at zero, not a missing bar

        while state.exports.exportInProgress != nil { await Task.yield() }
        #expect(state.exports.exportProgress == nil) // cleared, so no stale bar outlives the export
    }

    @Test func aReportedFractionReachesTheMenu() async {
        let state = makeState()
        state.notifier = { _ in }
        let release = Box<Bool>()
        state.exports.exportFunction = { _, output, _, _, _, progress in
            progress(0.42)
            while release.value != true { await Task.yield() }
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        // The exporter reports from a background queue, so the value lands after a hop. Bounded:
        // a fraction that never arrives must fail the test rather than hang it.
        var spins = 0
        while state.exports.exportProgress != 0.42, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
        #expect(state.exports.exportProgress == 0.42)

        release.value = true
        while state.exports.exportInProgress != nil { await Task.yield() }
    }

    @Test func aGifHasNoProgressToShow() async {
        // Nothing in the GIF path can report, and an invented figure is worse than none.
        let state = makeState()
        state.notifier = { _ in }
        state.exports.gifExportFunction = { _, output, _ in output }

        state.exportToGIF(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exports.exportInProgress == "Clip.mov")
        #expect(state.exports.exportProgress == nil)

        while state.exports.exportInProgress != nil { await Task.yield() }
    }
}
