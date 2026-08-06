import CoreGraphics
import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// M12-T3 "the menu tells the truth": the pure label strings the submenu titles carry, and the
/// staleness that expires a persisted export receipt.
@MainActor
@Suite struct MenuTruthTests {

    private func makeState() -> AppState {
        AppState(defaults: TestDefaults.make())
    }

    // MARK: - Source label

    @Test func sourceLabelIsPlainEntireScreenWithOneDisplay() {
        let state = makeState()
        state.refreshSources(displays: [DisplayOption(id: 1, name: "Built-in", isMain: true)])
        #expect(state.sources.sourceMenuLabel == "Entire Screen")     // no display name when there's no choice
    }

    @Test func sourceLabelNamesTheDisplayWhenThereIsAChoice() {
        let state = makeState()
        state.refreshSources(displays: [
            DisplayOption(id: 1, name: "Sidecar", isMain: false),
            DisplayOption(id: 2, name: "Built-in Retina Display", isMain: true),
        ])
        #expect(state.sources.sourceMenuLabel == "Entire Screen (Built-in Retina Display)")
    }

    @Test func sourceLabelNamesWhatIsLeftOut() {
        // M21-T4: the pick is still whole-screen, so the label says so and then what's missing.
        let state = makeState()
        state.refreshSources(displays: [DisplayOption(id: 1, name: "Built-in", isMain: true)])
        state.refreshApps(
            [CapturableApp(bundleID: "com.spotify.client", name: "Spotify")], excluding: nil)
        state.sources.sourceChoice = .displayExcluding(bundleID: "com.spotify.client")
        #expect(state.sources.sourceMenuLabel == "Entire Screen except Spotify")
    }

    @Test func sourceLabelIsTheAppNameForAScopedPick() {
        let state = makeState()
        state.sources.appDisplayName = { $0 == "com.acme.app" ? "Acme" : nil }
        state.sources.sourceChoice = .app(bundleID: "com.acme.app")
        #expect(state.sources.sourceMenuLabel == "Acme")
    }

    @Test func sourceLabelIsTheRegionSizeForARegionPick() {
        let state = makeState()
        state.setRegion(displayID: nil, rect: CGRect(x: 0, y: 0, width: 820, height: 512))
        #expect(state.sources.sourceMenuLabel == "Region 820×512")
    }

    // MARK: - Microphone label

    @Test func microphoneLabelIsNoneAutomaticOrCollapsedAwayDevice() {
        let state = makeState()

        state.microphonePreference = .none
        #expect(state.microphoneMenuLabel == "None")

        state.microphonePreference = .automatic
        #expect(state.microphoneMenuLabel == "Automatic")

        // A picked device that isn't currently connected reads through `presentMicrophonePreference`
        // as None (the checkmark truth) — never a device name for a mic in its case.
        state.microphonePreference = .device(id: "not-connected")
        #expect(state.microphoneMenuLabel == "None")
    }

    @Test func microphoneLabelIsTheDeviceNameForAConnectedPick() {
        // The `.device` branch needs a real connected mic; `microphones` comes from the system with
        // no injectable seam, so this exercises the branch where one exists (the dev box) and no-ops
        // in a mic-less CI. The away-device case above covers the collapse-to-None fallback.
        let state = makeState()
        state.refreshSources(displays: [])            // populates `microphones` from the system
        guard let device = state.microphones.first else { return }
        state.microphonePreference = .device(id: device.uniqueID)
        #expect(state.microphoneMenuLabel == device.name)
    }

    // MARK: - The take receipt (M24-T3)

    private static let take = URL(fileURLWithPath: "/tmp/Recording 2026-07-31 at 11.26.54.mov")

    @Test func theTakeReceiptNamesItsLengthRatherThanItsTimestamp() {
        // The finding is that a take is "identified by timestamp"; a receipt titled with the
        // filename would move that problem rather than fix it.
        let state = makeState()
        state.finishTake((url: Self.take, duration: 22.4))
        #expect(state.lastRecording?.menuTitle == "Recording saved · 0:22")
        #expect(state.lastRecording?.url == Self.take)
    }

    @Test func anEndingThatLeavesNoFileRaisesNoReceipt() {
        // A discard, a start that failed, a `.writeFailed` — `finishedRecording` is nil for all
        // three, and a row pointing at nothing is worse than no row.
        let state = makeState()
        state.finishTake(nil)
        #expect(state.lastRecording == nil)
    }

    @Test func theTakeReceiptExpiresPastTheHourOrWhenItsFileIsGone() throws {
        let file = try sizedFile(bytes: 16)
        defer { try? FileManager.default.removeItem(at: file) }
        let state = makeState()

        state.finishTake((url: file, duration: 5))
        state.expireStaleRecordingReceipt()
        #expect(state.lastRecording != nil)          // fresh, and its file is there

        try FileManager.default.removeItem(at: file)
        state.expireStaleRecordingReceipt()
        #expect(state.lastRecording == nil)          // the row's every action would be a no-op
    }

    @Test func aTakeReceiptOlderThanTheExportWindowIsDropped() {
        // Same clock as the export receipt (M12-T3), so there is one rule rather than two.
        let state = makeState()
        state.finishTake((url: Self.take, duration: 5))
        let old = LastRecording(
            url: Self.take, duration: 5,
            date: Date(timeIntervalSinceNow: -ExportModel.receiptFreshness - 1))
        #expect(old.isStale(now: Date(), freshFor: ExportModel.receiptFreshness))
        #expect(state.lastRecording?.isStale(
            now: Date(), freshFor: ExportModel.receiptFreshness) == false)
    }

    /// A real file of a known size, for the paths that check one exists.
    private func sizedFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("menutruth-\(UUID().uuidString).mov")
        try Data(count: bytes).write(to: url)
        return url
    }

    // MARK: - Which Stop row owns the shortcut (M24-T2)

    @Test func exactlyOneStopRowAdvertisesTheShortcutAndItIsTheOneTheKeyPerforms() {
        // The mitigation for one combo having two meanings: the menu names the live one. If both
        // rows printed it, or the wrong one did, the menu would be the lie this suite exists for.
        let state = makeState()
        state.recordHotkey = .recordDefault

        #expect(state.stopAndSaveHotkey == .recordDefault)
        #expect(state.stopAndCopyHotkey == nil)

        state.stopHotkeyCopies = true
        #expect(state.stopAndSaveHotkey == nil)
        #expect(state.stopAndCopyHotkey == .recordDefault)

        // Shortcut off: neither row claims one, whatever the ending says.
        state.recordHotkey = nil
        #expect(state.stopAndSaveHotkey == nil)
        #expect(state.stopAndCopyHotkey == nil)
    }

    // MARK: - Receipt staleness

    @Test func aReceiptIsStaleOnlyAfterTheFreshnessWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let url = URL(fileURLWithPath: "/tmp/x.mp4")

        #expect(!LastExport(url: url, date: now).isStale(now: now, freshFor: 3600))            // 0 s
        #expect(!LastExport(url: url, date: now.addingTimeInterval(-3600))                     // exactly the
            .isStale(now: now, freshFor: 3600))                                                // window: fresh
        #expect(LastExport(url: url, date: now.addingTimeInterval(-3601))                      // one past it:
            .isStale(now: now, freshFor: 3600))                                                // stale
    }

    @Test func expireDropsAStaleReceiptButKeepsAFreshOne() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Clip.mp4")
        try Data("x".utf8).write(to: file)

        // Stale: persisted two hours ago, past the one-hour window → expiry drops it.
        let staleDefaults = TestDefaults.make()
        SettingsStore.saveLastExport(
            LastExport(url: file, date: Date(timeIntervalSinceNow: -7200)), to: staleDefaults)
        let staleState = AppState(defaults: staleDefaults)
        #expect(staleState.exports.lastExport != nil)                 // seeded (existence only, staleness later)
        staleState.exports.expireStaleReceipt()
        #expect(staleState.exports.lastExport == nil)

        // Fresh: persisted just now → expiry keeps it.
        let freshDefaults = TestDefaults.make()
        SettingsStore.saveLastExport(LastExport(url: file, date: Date()), to: freshDefaults)
        let freshState = AppState(defaults: freshDefaults)
        freshState.exports.expireStaleReceipt()
        #expect(freshState.exports.lastExport?.url == file)
    }

    // MARK: - System audio (M16-T3, ADR-019)

    @Test func systemAudioIsOnUntilTurnedOffAndSurvivesRelaunch() {
        let defaults = TestDefaults.make()
        // Absent ⇒ on, so existing installs keep capturing it (the showsMenuBarTimer idiom).
        #expect(AppState(defaults: defaults).capturesSystemAudio)

        let state = AppState(defaults: defaults)
        state.capturesSystemAudio = false
        #expect(!state.captureConfiguration.capturesSystemAudio)
        #expect(!AppState(defaults: defaults).capturesSystemAudio)   // round-trips
    }

    @Test func onlyASilentConfigurationSaysItWillBeSilent() {
        let state = makeState()
        #expect(state.silentRecordingWarning == nil)          // system audio on, mic None

        state.capturesSystemAudio = false
        #expect(state.silentRecordingWarning == "This recording will have no audio")

        state.microphonePreference = .automatic
        #expect(state.silentRecordingWarning == nil)          // a mic is still audio
    }

    // MARK: - What an armed buffer costs (M16-T2)

    /// The measured geometry of this machine's display: 2056×1285 pt at 2× ⇒ the 4112×2570 frames
    /// SCK delivers.
    private func retinaDisplay(id: CGDirectDisplayID = 1) -> DisplayOption {
        DisplayOption(
            id: id, name: "Built-in Retina Display", isMain: true,
            pointSize: CGSize(width: 2056, height: 1285), pointPixelScale: 2)
    }

    @Test func bufferCostNamesMemoryThenWakefulness() {
        let state = makeState()
        state.refreshSources(displays: [retinaDisplay()])
        state.replaySeconds = 60
        state.frameRateCap = 60
        state.microphonePreference = .automatic

        #expect(state.replayBufferCaption(seconds: 60)
            == "A 1-minute buffer holds about 180 MB in memory. "
                + "While armed, ScreenRec keeps your Mac awake.")
        #expect(state.replayBufferMenuLabel == "1 min buffer · ≈180 MB · Mac stays awake")
    }

    // MARK: - What the buffer actually holds (M36-T2)

    /// 🔴 The row used to state the *configured* window unconditionally. A ring restarts empty after
    /// any stream death — a display sleep, a source change — so it could promise two minutes while
    /// holding four seconds, and `Save Replay Now` then handed over a fraction with no warning.
    @Test func theRowSaysWhatIsHeldWhileTheBufferIsStillShort() {
        #expect(AppState.bufferHolding(120, held: 12) == "0:12 of 2 min held")
        #expect(AppState.bufferHolding(120, held: 63.31) == "1:03 of 2 min held")
        #expect(AppState.bufferHolding(60, held: 0) == "0:00 of 1 min held")
    }

    /// Full reads as full, and the wording returns to exactly what it always was — silence when there
    /// is nothing to say. ⚠️ Within a second counts as full: newest-minus-oldest never quite equals
    /// the window, and "1:59 of 2 min held" forever would be worse than saying nothing.
    @Test func aFullBufferGoesBackToNamingTheWindow() {
        #expect(AppState.bufferHolding(120, held: 120) == "2 min buffer")
        #expect(AppState.bufferHolding(120, held: 119.4) == "2 min buffer")
        #expect(AppState.bufferHolding(120, held: 200) == "2 min buffer")     // can't exceed it
    }

    /// Nothing armed ⇒ nothing measured. The row doesn't exist then, but the phrase must not invent
    /// a figure if it is ever asked.
    @Test func nothingHeldAndNothingArmedBothNameTheWindow() {
        #expect(AppState.bufferHolding(120, held: nil) == "2 min buffer")
        // docs/02 §10: CMTime → seconds can be NaN, and a NaN must never reach the row.
        #expect(AppState.bufferHolding(120, held: .nan) == "2 min buffer")
        // ⚠️ NaN alone does not exercise the `isFinite` guard — every NaN comparison is false, so it
        // falls through to the window phrase anyway. Negative infinity is what the guard is for.
        #expect(AppState.bufferHolding(120, held: -.infinity) == "2 min buffer")
        #expect(AppState.bufferHolding(120, held: .infinity) == "2 min buffer")
    }

    /// 🔴 The break sweep found this untested: a spy overrides `heldSeconds()` wholesale, so the real
    /// controller's max-of-rings policy had no coverage at all. Pinned as a pure function instead.
    @Test func theHoldingIsTheLargerRingNotTheVideoOne() {
        // A static screen: video stale, audio flowing — the buffer would still save a full window.
        #expect(ReplayController.heldSeconds(video: 3, audio: 118) == 118)
        // A silent take: audio ring absent, video is all there is.
        #expect(ReplayController.heldSeconds(video: 42, audio: nil) == 42)
        #expect(ReplayController.heldSeconds(video: 0, audio: nil) == 0)
    }

    /// The whole row, through the injected controller rather than the pure helper — so the wiring
    /// from ring to menu is covered, not just the phrasing.
    @MainActor
    @Test func theArmedRowCarriesTheHoldingThroughTheController() {
        let spy = ReplayWiringTests.ReplaySpy()
        spy.held = 9
        let state = AppState(defaults: TestDefaults.make(), replayController: spy)
        state.refreshSources(displays: [retinaDisplay()])
        state.replaySeconds = 60
        state.frameRateCap = 60
        state.microphonePreference = .automatic

        #expect(state.replayBufferMenuLabel == "0:09 of 1 min held · ≈180 MB · Mac stays awake")
    }

    @Test func aMicrophoneThatWontBeCapturedIsntBilledFor() {
        let state = makeState()
        state.refreshSources(displays: [retinaDisplay()])
        state.replaySeconds = 60
        state.frameRateCap = 60
        // Default pick is None — no mic ring, so the quote drops the mic's share.
        #expect(state.replayBufferMenuLabel == "1 min buffer · ≈170 MB · Mac stays awake")

        // An away device reads None in the menu and must read None here too (M8-T2's checkmark truth).
        state.microphonePreference = .device(id: "absent-device")
        #expect(state.replayBufferMenuLabel == "1 min buffer · ≈170 MB · Mac stays awake")
    }

    @Test func bufferCostWithholdsTheFigureUntilTheScreenListArrives() {
        // No geometry ⇒ no number invented; the standing fact still gets said.
        let state = makeState()
        #expect(state.replayBufferBytes(seconds: 60) == nil)
        #expect(state.replayBufferCaption(seconds: 60)
            == "While armed, ScreenRec keeps your Mac awake.")
        #expect(state.replayBufferMenuLabel == "Mac stays awake while armed")
    }

    @Test func theCaptionQuotesTheWindowItIsAskedAbout() {
        let state = makeState()
        state.refreshSources(displays: [retinaDisplay()])
        state.replaySeconds = 60
        // The slider passes its in-progress value, so the caption moves with the drag.
        #expect(state.replayBufferCaption(seconds: 900).contains("A 15-minute buffer"))
        #expect(state.replayBufferCaption(seconds: 900) != state.replayBufferCaption(seconds: 60))
    }

    @Test func aRegionPickIsBilledForItsOwnPixels() {
        let state = makeState()
        state.refreshSources(displays: [retinaDisplay()])
        let whole = state.replayBufferBytes(seconds: 60)
        state.sources.sourceChoice = .region(display: 1, rect: CGRect(x: 0, y: 0, width: 800, height: 600))
        let region = state.replayBufferBytes(seconds: 60)
        #expect(region != nil && whole != nil)
        #expect(region! < whole!)
    }

    @Test func anAppScopedPickIsBilledForTheMainDisplayItCompositesOn() {
        // 02 §1a: an app filter composites on the MAIN display, whichever display the pickers
        // remember — so picking a small second screen then an app must not shrink the quote.
        let state = makeState()
        state.refreshSources(displays: [
            retinaDisplay(),
            DisplayOption(
                id: 2, name: "Sidecar", isMain: false,
                pointSize: CGSize(width: 1024, height: 768), pointPixelScale: 1),
        ])
        state.sources.sourceChoice = .display(2)
        let sidecarQuote = state.replayBufferBytes(seconds: 60)

        state.sources.appDisplayName = { _ in "Acme" }
        state.sources.sourceChoice = .app(bundleID: "com.acme.app")
        let appQuote = state.replayBufferBytes(seconds: 60)

        state.sources.sourceChoice = .display(1)
        let mainQuote = state.replayBufferBytes(seconds: 60)

        #expect(appQuote == mainQuote)          // composites on main…
        #expect(appQuote != sidecarQuote)       // …not the display the pickers remember
    }

    @Test func bufferPhrasesReadNaturallyAcrossTheSliderRange() {
        #expect(AppState.bufferPhrase(45) == "45-second")
        #expect(AppState.bufferPhrase(60) == "1-minute")
        #expect(AppState.bufferPhrase(105) == "1:45")
        #expect(AppState.bufferPhrase(900) == "15-minute")
        #expect(AppState.shortBufferPhrase(45) == "45 s")
        #expect(AppState.shortBufferPhrase(60) == "1 min")
        #expect(AppState.shortBufferPhrase(105) == "1:45")
        #expect(AppState.shortBufferPhrase(900) == "15 min")
    }
}
