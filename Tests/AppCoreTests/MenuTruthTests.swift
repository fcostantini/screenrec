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
