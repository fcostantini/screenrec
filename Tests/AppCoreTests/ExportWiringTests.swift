import Foundation
import Testing

@testable import AppCore
import RecorderCore

/// Records the config an injected GIF export was handed (the closure is `@Sendable`).
private final class ConfigBox: @unchecked Sendable {
    var value: GifConfiguration?
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
        state.exportFunction = { _, _ in written }

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
        state.exportFunction = { _, _ in throw ExportError.writerFailed("nope") }

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
        state.exportFunction = { _, _ in firstURL }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/A.mov"))
        while state.exportInProgress != nil { await Task.yield() }
        #expect(state.lastExport?.url == firstURL)

        state.exportFunction = { _, _ in throw ExportError.writerFailed("nope") }
        state.exportToMP4(URL(fileURLWithPath: "/tmp/B.mov"))
        while state.exportInProgress != nil { await Task.yield() }
        #expect(state.lastExport?.url == firstURL)   // A's pointer isn't erased by B's failure
    }

    @Test func secondExportWhileOneRunsIsIgnored() async {
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.exportFunction = { _, output in output }

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
        state.gifExportFunction = { _, _, _ in written }

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
        let recorded = ConfigBox()
        state.gifExportFunction = { _, output, configuration in
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

    @Test func oneExportAtATimeAcrossFormats() async {
        let state = makeState()
        state.notifier = { _ in }
        state.exportFunction = { _, output in output }
        state.gifExportFunction = { _, output, _ in output }

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
