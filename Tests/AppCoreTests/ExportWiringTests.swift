import Foundation
import Testing

@testable import AppCore
import RecorderCore

/// Records what an injected export/trim was handed (the closures are `@Sendable`).
private final class Box<Value>: @unchecked Sendable {
    var value: Value?
}

/// AppState → Exporter wiring, with the transcode injected — the real `Exporter` runs the
/// hardware encoder (that's `ExporterTests`' job), so the wiring is tested on a fake.
@MainActor
@Suite struct ExportWiringTests {

    private func makeState() -> AppState {
        AppState(defaults: UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!)
    }

    @Test func exportSetsInProgressSynchronouslyThenReceiptAndNotifies() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let written = URL(fileURLWithPath: "/tmp/Clip.mp4")
        state.exports.exportFunction = { _, _, _ in written }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exportInProgress == "Clip.mov")   // set before the background task runs
        #expect(state.lastExport == nil)

        while state.exportInProgress != nil { await Task.yield() }

        #expect(state.lastExport?.url == written)
        #expect(state.lastExport?.menuTitle == "Exported to MP4 · Clip.mp4")
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Exported to MP4")
        #expect(posted.first?.fileURL == written)
    }

    @Test func exportFailureNotifiesAndLeavesNoReceipt() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.exports.exportFunction = { _, _, _ in throw ExportError.writerFailed("nope") }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exportInProgress != nil { await Task.yield() }

        #expect(state.lastExport == nil)
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Couldn't export to MP4")
        #expect(posted.first?.fileURL == nil)
    }

    @Test func aFailedReExportKeepsThePriorReceipt() async {
        let state = makeState()
        state.notifier = { _ in }
        let firstURL = URL(fileURLWithPath: "/tmp/A.mp4")
        state.exports.exportFunction = { _, _, _ in firstURL }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        while state.exportInProgress != nil { await Task.yield() }
        #expect(state.lastExport?.url == firstURL)

        state.exports.exportFunction = { _, _, _ in throw ExportError.writerFailed("nope") }
        state.exportToMP4(URL(fileURLWithPath: "/tmp/B.mov"))
        while state.exportInProgress != nil { await Task.yield() }
        #expect(state.lastExport?.url == firstURL)   // A's pointer isn't erased by B's failure
    }

    @Test func secondExportWhileOneRunsIsIgnored() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.exports.exportFunction = { _, output, _ in output }

        // No suspension point between the two calls, so the first export's task hasn't run yet —
        // the guard sees `exportInProgress` set and drops the second.
        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        state.exportToMP4(URL(fileURLWithPath: "/tmp/B.mov"))
        #expect(state.exportInProgress == "A.mov")

        while state.exportInProgress != nil { await Task.yield() }
        #expect(posted.count == 1)   // exactly one export completed
    }

    @Test func gifExportSetsReceiptAndNotifies() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let written = URL(fileURLWithPath: "/tmp/Clip.gif")
        state.exports.gifExportFunction = { _, _, _ in written }

        state.exportToGIF(URL(fileURLWithPath: "/tmp/Clip.mov"))
        #expect(state.exportInProgress == "Clip.mov")
        while state.exportInProgress != nil { await Task.yield() }

        #expect(state.lastExport?.url == written)
        #expect(state.lastExport?.menuTitle == "Saved as GIF · Clip.gif")
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
        while state.exportInProgress != nil { await Task.yield() }

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
        state.exports.exportFunction = { _, output, configuration in
            recorded.value = configuration
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        while state.exportInProgress != nil { await Task.yield() }

        #expect(recorded.value?.maxWidth == 2560)
        // The height ceiling is not a preference: it is what keeps the output inside H.264
        // Level 5.2 (docs/02 §3), so every pick carries it.
        #expect(recorded.value?.maxHeight == 2304)
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

    @Test func oneExportAtATimeAcrossFormats() async {
        let state = makeState()
        state.notifier = { _ in }
        state.exports.exportFunction = { _, output, _ in output }
        state.exports.gifExportFunction = { _, output, _ in output }

        // An MP4 in flight blocks a GIF (they share one guard); no await between, so the MP4
        // task hasn't run yet.
        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        state.exportToGIF(URL(fileURLWithPath: "/tmp/A.mov"))
        #expect(state.exportInProgress == "A.mov")
        while state.exportInProgress != nil { await Task.yield() }
        // The receipt is the MP4 sibling, not the GIF — the GIF call was dropped.
        #expect(state.lastExport?.url.pathExtension == "mp4")
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
        state.exports.trimFunction = { _, _, start, end, mode in
            range.value = (start, end, mode)
            return written
        }

        state.trim(URL(fileURLWithPath: "/tmp/Clip.mov"), from: 2, to: 8)
        #expect(state.exportInProgress == "Clip.mov")
        while state.exportInProgress != nil { await Task.yield() }

        #expect(range.value?.start == 2)
        #expect(range.value?.end == 8)
        #expect(range.value?.mode == .lossless)  // the default stays lossless (ADR-015)
        #expect(state.lastExport?.url == written)
        #expect(state.lastExport?.menuTitle == "Trimmed · Clip trimmed.mov")  // .mov ⇒ "Trimmed"
        #expect(posted.first?.title == "Trimmed")
        #expect(posted.first?.fileURL == written)
    }

    @Test func theTrimWindowsReencodeToggleReachesTheTrim() async {
        // The window's checkbox is the only way to ask for a re-encode; if it stopped arriving,
        // the trim would quietly stay lossless and keep the lead-in it promised to drop (M18-T1).
        let state = makeState()
        let range = Box<(start: Double, end: Double, mode: TrimMode)>()
        state.exports.trimFunction = { _, _, start, end, mode in
            range.value = (start, end, mode)
            return URL(fileURLWithPath: "/tmp/Clip trimmed.mov")
        }

        state.trim(URL(fileURLWithPath: "/tmp/Clip.mov"), from: 2, to: 8, mode: .precise)
        while state.exportInProgress != nil { await Task.yield() }

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
}
