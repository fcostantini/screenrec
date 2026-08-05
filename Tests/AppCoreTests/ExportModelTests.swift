import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// The export/trim sub-model split from AppState (M14-T1), tested by name (M23-T4).
///
/// `ExportWiringTests` drives the same model through `AppState` and keeps doing so; these assert
/// the model's own rules one layer down, so a break reports as `ExportModelTests`. The real
/// transcode is injected throughout — `ExporterTests` owns the hardware encoder.
@MainActor
@Suite struct ExportModelTests {

    private static let source = URL(fileURLWithPath: "/tmp/Clip.mov")

    private func makeModel() -> ExportModel {
        ExportModel(defaults: TestDefaults.make())
    }

    /// Bounded, per M15-T1: a queue that never drains is a **hang**, and a regression has to fail
    /// this suite rather than wedge it. The sweep proved the point — removing `finish()` hung the
    /// run instead of turning it red, until this yield budget was added.
    private func settle(_ model: ExportModel, file: StaticString = #file, line: UInt = #line) async {
        for _ in 0..<10_000 {
            guard model.exportInProgress != nil || model.queuedExportCount > 0 else { return }
            await Task.yield()
        }
        Issue.record("exports never settled — \(model.queuedExportCount) still queued")
    }

    // MARK: - One export at a time (M10-T2)

    @Test func inProgressIsSetSynchronouslyBeforeTheTaskRuns() async {
        // Set inside the Task instead, and the menu offers a second export in the gap — which the
        // guard below then can't see.
        let model = makeModel()
        model.exportFunction = { _, output, _, _, _, _ in output }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        #expect(model.exportInProgress == "Clip.mov")
        await settle(model)
    }

    /// M33-T1 replaced the old contract here. Until then a second request while one ran was
    /// **dropped** — this test asserted that. It now has to wait its turn instead, and the strong
    /// form of that is: both run, in the order asked, and the queue drains to empty.
    @Test func aSecondExportWhileOneRunsWaitsItsTurnRatherThanBeingDropped() async {
        let model = makeModel()
        var posted: [RecordingNotification] = []
        model.notify = { posted.append($0) }
        let ran = Trail()
        model.exportFunction = { source, output, _, _, _, _ in
            ran.append(source.lastPathComponent)
            return output
        }

        // No suspension point between the calls, so the first task hasn't run yet.
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        model.exportToMP4(URL(fileURLWithPath: "/tmp/Other.mov"), configuration: ExportConfiguration())
        #expect(model.exportInProgress == "Clip.mov")   // the first still runs immediately
        #expect(model.queuedExportCount == 1)           // and the second is behind it, not gone

        await settle(model)
        #expect(ran.items == ["Clip.mov", "Other.mov"])       // FIFO, not whichever finished first
        #expect(posted.count == 2)                      // each gets its own notice
        #expect(model.queuedExportCount == 0)
        #expect(model.exportInProgress == nil)
    }

    /// A job that fails must not strand the ones behind it — every ending routes through `finish()`.
    @Test func aFailureInTheMiddleStillReleasesTheQueue() async {
        let model = makeModel()
        let ran = Trail()
        model.notify = { _ in }
        model.exportFunction = { source, output, _, _, _, _ in
            ran.append(source.lastPathComponent)
            if source.lastPathComponent == "B.mov" { throw ExportError.readerFailed("boom") }
            return output
        }
        for name in ["A.mov", "B.mov", "C.mov"] {
            model.exportToMP4(URL(fileURLWithPath: "/tmp/\(name)"), configuration: ExportConfiguration())
        }
        await settle(model)
        #expect(ran.items == ["A.mov", "B.mov", "C.mov"])
        #expect(model.queuedExportCount == 0)
    }

    /// Quitting means quitting: "Quit Anyway" drops the whole backlog, which is why the menu's
    /// confirmation states how many (M33-T1).
    @Test func cancellingClearsTheQueueAndNotJustTheRunner() async {
        let model = makeModel()
        model.notify = { _ in }
        model.exportFunction = { _, output, _, _, _, _ in output }
        for name in ["A.mov", "B.mov", "C.mov"] {
            model.exportToMP4(URL(fileURLWithPath: "/tmp/\(name)"), configuration: ExportConfiguration())
        }
        #expect(model.queuedExportCount == 2)
        model.cancelExport()
        #expect(model.queuedExportCount == 0)
        #expect(model.exportInProgress == nil)
    }

    @Test func inProgressClearsOnFailureSoTheNextExportIsNotWedged() async {
        // Clearing only on success wedges every later export behind one failure.
        let model = makeModel()
        model.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        await settle(model)
        #expect(model.exportInProgress == nil)

        model.exportFunction = { _, output, _, _, _, _ in output }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        #expect(model.exportInProgress == "Clip.mov")   // the next one is accepted
        await settle(model)
    }

    @Test func inProgressClearsWhenAnExportIsRefusedForRoom() async {
        let model = makeModel()
        model.availableBytes = { _ in 0 }
        let ran = Box<Bool>()
        model.trimFunction = { _, output, _, _, _, _ in ran.value = true; return output }

        let file = try? sizedFile(bytes: 2048)
        defer { file.map { try? FileManager.default.removeItem(at: $0) } }
        model.trim(file ?? Self.source, from: 0, to: 1, mode: .lossless)
        await settle(model)

        #expect(model.exportInProgress == nil)
        #expect(ran.value != true)
    }

    // MARK: - Copying a range (M24-T1)

    @Test func aRangedCopyWritesTheTrimmedSiblingSoAClipCannotPassForTheTake() async {
        let model = makeModel()
        model.copyToPasteboard = { _ in }
        let written = Box<URL>()
        model.exportFunction = { _, output, _, _, _, _ in written.value = output; return output }

        model.exportAndCopy(
            Self.source, configuration: ExportConfiguration(),
            range: ExportRange(start: 1, end: 3))
        await settle(model)

        #expect(written.value?.lastPathComponent == "Clip trimmed.mp4")
    }

    @Test func aCopyWithNoRangeStillWritesTheTakesOwnMP4() async {
        // The control: Stop & Copy (M21-T2) passes no range, and its output name must not move.
        let model = makeModel()
        model.copyToPasteboard = { _ in }
        let written = Box<URL>()
        model.exportFunction = { _, output, _, _, _, _ in written.value = output; return output }

        model.exportAndCopy(Self.source, configuration: ExportConfiguration())
        await settle(model)

        #expect(written.value?.lastPathComponent == "Clip.mp4")
    }

    @Test func theRangeReachesTheExporter() async {
        // Naming the output alone would hand back the whole take under the clip's name.
        let model = makeModel()
        model.copyToPasteboard = { _ in }
        let seen = Box<ExportRange>()
        model.exportFunction = { _, output, _, range, _, _ in seen.value = range; return output }

        model.exportAndCopy(
            Self.source, configuration: ExportConfiguration(),
            range: ExportRange(start: 1.5, end: 4.25))
        await settle(model)

        #expect(seen.value == ExportRange(start: 1.5, end: 4.25))
    }

    @Test func theCropReachesTheExporter() async {
        // The window can draw a rectangle all it likes; this is the only thing that makes it real.
        let model = makeModel()
        model.copyToPasteboard = { _ in }
        let seen = Box<CropRect>()
        model.exportFunction = { _, output, _, _, crop, _ in seen.value = crop; return output }

        model.exportAndCopy(
            Self.source, configuration: ExportConfiguration(),
            crop: CropRect(x: 400, y: 300, width: 1600, height: 1000))
        await settle(model)

        #expect(seen.value == CropRect(x: 400, y: 300, width: 1600, height: 1000))
    }

    @Test func aRangedCopyPostsOneNoticeForTheFileItPutOnThePasteboard() async {
        let model = makeModel()
        var posted: [RecordingNotification] = []
        model.notify = { posted.append($0) }
        let copied = Box<URL>()
        model.copyToPasteboard = { copied.value = $0 }
        model.exportFunction = { _, output, _, _, _, _ in output }

        model.exportAndCopy(
            Self.source, configuration: ExportConfiguration(),
            range: ExportRange(start: 0, end: 2))
        await settle(model)

        #expect(copied.value?.lastPathComponent == "Clip trimmed.mp4")
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Copied — ⌘V to paste")
        #expect(posted.first?.fileURL == copied.value)
    }

    // MARK: - Receipt policy (M12-T2/T3)

    @Test func onlyASuccessSetsTheReceipt() async {
        let model = makeModel()
        let written = URL(fileURLWithPath: "/tmp/Clip.mp4")
        model.exportFunction = { _, _, _, _, _, _ in written }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        await settle(model)
        #expect(model.lastExport?.url == written)
    }

    @Test func aFailureLeavesNoReceiptAtAll() async {
        // A receipt here points the menu at a file that was never written.
        let model = makeModel()
        model.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        await settle(model)
        #expect(model.lastExport == nil)
    }

    @Test func aFailedReExportKeepsThePriorReceipt() async {
        // The "Exporting…" row shadows the receipt while running; a failure must restore it rather
        // than destroy a good pointer.
        let model = makeModel()
        let first = URL(fileURLWithPath: "/tmp/First.mp4")
        model.exportFunction = { _, _, _, _, _, _ in first }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        await settle(model)

        model.exportFunction = { _, _, _, _, _, _ in throw ExportError.writerFailed("nope") }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        await settle(model)
        #expect(model.lastExport?.url == first)
    }

    @Test func aReceiptExpiresOnAgeEvenWhenItsFileIsThere() throws {
        let file = try sizedFile(bytes: 16)
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        SettingsStore.saveLastExport(
            LastExport(url: file, date: Date(timeIntervalSinceNow: -7200)), to: defaults)

        let model = ExportModel(defaults: defaults)
        model.expireStaleReceipt()
        #expect(model.lastExport == nil)
    }

    @Test func aReceiptExpiresWhenItsFileIsGoneEvenWhenFresh() throws {
        // Checked at menu open, not only at launch: a file trashed mid-session would otherwise
        // leave a row whose every action silently does nothing (M18-T4).
        let file = try sizedFile(bytes: 16)
        let defaults = TestDefaults.make()
        SettingsStore.saveLastExport(LastExport(url: file, date: Date()), to: defaults)
        let model = ExportModel(defaults: defaults)
        #expect(model.lastExport != nil)

        try FileManager.default.removeItem(at: file)
        model.expireStaleReceipt()
        #expect(model.lastExport == nil)
    }

    @Test func aFreshReceiptWithItsFilePresentSurvives() throws {
        // The negative control: expiring everything would pass both tests above.
        let file = try sizedFile(bytes: 16)
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        SettingsStore.saveLastExport(LastExport(url: file, date: Date()), to: defaults)

        let model = ExportModel(defaults: defaults)
        model.expireStaleReceipt()
        #expect(model.lastExport?.url == file)
    }

    @Test func renamingRePointsTheReceiptAndKeepsItsOriginalTime() throws {
        // Stamping `Date()` here would make a renamed old receipt fresh again and resurface it.
        let file = try sizedFile(bytes: 16)
        defer { try? FileManager.default.removeItem(at: file) }
        let exportedAt = Date(timeIntervalSinceNow: -600)
        let defaults = TestDefaults.make()
        SettingsStore.saveLastExport(LastExport(url: file, date: exportedAt), to: defaults)
        let model = ExportModel(defaults: defaults)

        let renamed = file.deletingLastPathComponent().appendingPathComponent("Renamed.mp4")
        model.renameReceipt(from: file, to: renamed)
        #expect(model.lastExport?.url == renamed)
        #expect(model.lastExport?.date == exportedAt)
    }

    @Test func trashingClearsTheReceiptAndAnotherFileDoesNot() throws {
        let file = try sizedFile(bytes: 16)
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = TestDefaults.make()
        SettingsStore.saveLastExport(LastExport(url: file, date: Date()), to: defaults)
        let model = ExportModel(defaults: defaults)

        model.clearReceipt(for: URL(fileURLWithPath: "/tmp/Unrelated.mp4"))
        #expect(model.lastExport != nil)          // someone else's trash must not clear it
        model.clearReceipt(for: file)
        #expect(model.lastExport == nil)
    }

    // MARK: - Quit seams (M23-T2)

    @Test func waitingReturnsOnlyAfterTheWorkSettles() async {
        // The whole point: quit must not be able to outrun the export it promised to wait for.
        let model = makeModel()
        let finished = Box<Bool>()
        model.exportFunction = { _, output, _, _, _, _ in
            try await Task.sleep(for: .milliseconds(30))
            finished.value = true
            return output
        }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        await model.waitForExportToFinish()
        #expect(finished.value == true)
        #expect(model.exportInProgress == nil)
    }

    @Test func waitingWithNothingRunningReturnsAtOnce() async {
        await makeModel().waitForExportToFinish()     // must not hang
    }

    @Test func abandoningClearsInFlightStateSynchronously() async {
        // `Quit Anyway` calls `terminate`, whose delegate waits for an export in flight — so the
        // clear must be visible before that check runs, or the button waits like the one beside it.
        let model = makeModel()
        model.exportFunction = { _, output, _, _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return output
        }
        model.exportToMP4(Self.source, configuration: ExportConfiguration())
        #expect(model.exportInProgress == "Clip.mov")

        model.cancelExport()
        #expect(model.exportInProgress == nil)        // no await between — that is the requirement
        await model.waitForExportToFinish()           // and quit's wait is now a no-op
        #expect(model.lastExport == nil)              // an abandoned export leaves no receipt
    }

    // MARK: - Fixtures

    /// A real file of a known size, for the estimate paths that read one.
    private func sizedFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exportmodel-\(UUID().uuidString).mp4")
        try Data(count: bytes).write(to: url)
        return url
    }
}
