import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// Persisted state is a different kind of risk from everything before it: in-memory state
/// self-corrects on the next launch, a bad plist value is the app's problem *at every launch
/// until someone fixes it*. And every case below is one `defaults write` away, so none of this
/// is hypothetical.
@Suite struct SettingsTests {

    /// A throwaway domain, so tests never read or scribble on the real preferences.
    /// Returns the name too, so a test can inspect that domain *alone* — the process's
    /// `dictionaryRepresentation()` also contains every inherited global, which is not what
    /// "what did we write" means.
    private func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        TestDefaults.makeNamed()
    }

    // MARK: - The contract

    /// `Settings.standard` with only the fields a test cares about overridden.
    private func makeSettings(
        outputDirectory: URL = URL(fileURLWithPath: "/tmp"),
        quality: QualityPreset = .balanced,
        frameRateCap: Int = 60
    ) -> Settings {
        var settings = Settings.standard
        settings.outputDirectory = outputDirectory
        settings.quality = quality
        settings.frameRateCap = frameRateCap
        return settings
    }

    @Test func keyNamesMatchTheSpecExactly() {
        // docs/06 calls these contractual and says do not rename. They're spelled once in
        // SettingsStore.Key; this is the assertion that ties that spelling to the document —
        // a typo here would surface a milestone later, in a task that assumes it's at fault.
        #expect(SettingsStore.Key.outputDirectory == "outputDirectory")
        #expect(SettingsStore.Key.qualityPreset == "qualityPreset")
        #expect(SettingsStore.Key.fpsCap == "fpsCap")
        #expect(SettingsStore.Key.microphoneID == "microphoneID")
        #expect(SettingsStore.Key.captureAppBundleID == "captureAppBundleID")
        #expect(SettingsStore.Key.captureRegion == "captureRegion")
        #expect(SettingsStore.Key.regionDisplay == "display")
        #expect(SettingsStore.Key.regionX == "x")
        #expect(SettingsStore.Key.regionY == "y")
        #expect(SettingsStore.Key.regionWidth == "width")
        #expect(SettingsStore.Key.regionHeight == "height")
        #expect(SettingsStore.Key.replayArmed == "replayArmed")
        #expect(SettingsStore.Key.replaySeconds == "replaySeconds")
        #expect(SettingsStore.Key.replayHotkey == "replayHotkey")
        #expect(SettingsStore.Key.recordHotkey == "recordHotkey")
        #expect(SettingsStore.Key.hotkeyKeyCode == "keyCode")
        #expect(SettingsStore.Key.hotkeyModifiers == "modifiers")
        #expect(SettingsStore.Key.showsMenuBarTimer == "showsMenuBarTimer")
        #expect(SettingsStore.Key.gifFPS == "gifFPS")
        #expect(SettingsStore.Key.gifWidth == "gifWidth")
        #expect(SettingsStore.Key.gifMaxSeconds == "gifMaxSeconds")
        #expect(SettingsStore.Key.lastExportPath == "lastExportPath")
        #expect(SettingsStore.Key.lastExportDate == "lastExportDate")
        #expect(SettingsStore.Key.seenReplayBannerWarning == "seenReplayBannerWarning")
        #expect(SettingsStore.Key.pauseHotkey == "pauseHotkey")
        #expect(SettingsStore.Key.countInEnabled == "countInEnabled")
    }

    // MARK: - Pause/resume shortcut + count-in (M12-T6)

    @Test func pauseHotkeyIsOptInAndRoundTrips() {
        let defaults = makeDefaults().defaults
        #expect(SettingsStore.load(from: defaults).pauseHotkey == nil)   // absent ⇒ off
        var settings = Settings.standard
        settings.pauseHotkey = .pauseDefault
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).pauseHotkey == .pauseDefault)

        // Turning it off clears the key back to absent (not a stale dict).
        settings.pauseHotkey = nil
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.dictionary(forKey: SettingsStore.Key.pauseHotkey) == nil)
        #expect(SettingsStore.load(from: defaults).pauseHotkey == nil)
    }

    @Test func aMalformedPauseHotkeyLoadsAsOff() {
        // Half a shortcut is not a shortcut — it falls back whole (the recordHotkey rule).
        let defaults = makeDefaults().defaults
        defaults.set(["keyCode": 35], forKey: SettingsStore.Key.pauseHotkey)   // no modifiers
        #expect(SettingsStore.load(from: defaults).pauseHotkey == nil)
    }

    @Test func countInEnabledRoundTripsAndDefaultsToOff() {
        let defaults = makeDefaults().defaults
        #expect(SettingsStore.load(from: defaults).countInEnabled == false)   // absent ⇒ off
        var settings = Settings.standard
        settings.countInEnabled = true
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).countInEnabled == true)
    }

    @Test func seenReplayBannerWarningRoundTripsAndDefaultsToFalse() {
        let defaults = makeDefaults().defaults
        #expect(SettingsStore.load(from: defaults).seenReplayBannerWarning == false)   // absent ⇒ not seen
        var settings = Settings.standard
        settings.seenReplayBannerWarning = true
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).seenReplayBannerWarning == true)
    }

    // MARK: - The export receipt (M12-T2)

    @Test func lastExportReceiptRoundTripsWhenTheFileExists() throws {
        let defaults = makeDefaults().defaults
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("receipt-\(UUID().uuidString).mp4")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let export = LastExport(url: file, date: Date(timeIntervalSince1970: 1_000_000))
        SettingsStore.saveLastExport(export, to: defaults)
        #expect(SettingsStore.loadLastExport(from: defaults) == export)   // url AND date survive
    }

    @Test func aReceiptWhoseFileIsGoneIsDroppedOnLoad() {
        // A persisted pointer to a file since moved or trashed must not resurface as a broken row.
        let defaults = makeDefaults().defaults
        SettingsStore.saveLastExport(
            LastExport(url: URL(fileURLWithPath: "/tmp/gone-\(UUID().uuidString).mp4"), date: Date()),
            to: defaults)
        #expect(SettingsStore.loadLastExport(from: defaults) == nil)
    }

    @Test func aPreT3ReceiptWithNoDateIsDroppedOnLoad() throws {
        // An entry persisted before M12-T3 has a path but no date; without a date it can't be aged,
        // so it's dropped rather than shown undismissable.
        let defaults = makeDefaults().defaults
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legacy-\(UUID().uuidString).mp4")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        defaults.set(file.path, forKey: SettingsStore.Key.lastExportPath)   // path only, no date
        #expect(SettingsStore.loadLastExport(from: defaults) == nil)
    }

    @Test func savingNilClearsBothReceiptKeys() {
        let defaults = makeDefaults().defaults
        SettingsStore.saveLastExport(
            LastExport(url: URL(fileURLWithPath: "/tmp/x.mp4"), date: Date()), to: defaults)
        SettingsStore.saveLastExport(nil, to: defaults)
        #expect(defaults.string(forKey: SettingsStore.Key.lastExportPath) == nil)
        #expect(defaults.object(forKey: SettingsStore.Key.lastExportDate) == nil)
    }

    @Test func anExcludedAppSurvivesRelaunchAndClearsCleanly() {
        // M21-T4, the app-pick rule: absence never re-homes it, so it has to come back on launch.
        let (defaults, _) = makeDefaults()
        var settings = Settings.standard
        settings.excludedAppBundleID = "com.spotify.client"
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).excludedAppBundleID == "com.spotify.client")

        settings.excludedAppBundleID = nil
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).excludedAppBundleID == nil)
        #expect(defaults.object(forKey: SettingsStore.Key.excludedAppBundleID) == nil)
    }

    @Test func savesUnderExactlyThoseKeysAndNoOthers() {
        // `defaults read` is how docs/03's verify inspects this, so what lands in our domain has
        // to be the documented keys and nothing else — no @AppStorage prefix, no stray extras.
        let (defaults, suite) = makeDefaults()
        SettingsStore.save(.standard, to: defaults)
        let written = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(written.keys) == [
            "outputDirectory", "qualityPreset", "fpsCap", "capturesSystemAudio",
            "replayArmed", "replaySeconds", "replayHotkey", "showsMenuBarTimer", "showsMenuBarLevel",
            "gifFPS", "gifWidth", "gifMaxSeconds", "mp4Width", "stopAfterMinutes",
            "seenReplayBannerWarning", "countInEnabled", "namesTakeOnStop",
        ])
    }

    @Test func qualityPersistsAsItsDocumentedString() {
        // docs/06: `efficient`|`balanced`|`high` — human-readable in `defaults read`, and the
        // literal M5 would have to match. An enum ordinal would be neither.
        let defaults = makeDefaults().defaults
        SettingsStore.save(makeSettings(quality: .high, frameRateCap: 30), to: defaults)
        #expect(defaults.string(forKey: "qualityPreset") == "high")
        #expect(defaults.integer(forKey: "fpsCap") == 30)
    }

    @Test func outputDirectoryPersistsAsAPathNotAnArchivedURL() {
        // docs/06 says String. A URL would archive as opaque data that `defaults read` can't
        // show a human — and the verify step is a human reading `defaults read`.
        let defaults = makeDefaults().defaults
        SettingsStore.save(makeSettings(), to: defaults)
        #expect(defaults.string(forKey: "outputDirectory") == "/tmp")
    }

    @Test func microphonePickPersistsAndSurvivesItsDeviceBeingAway() {
        let defaults = makeDefaults().defaults
        var settings = makeSettings()
        settings.microphonePreference = .device(id: "airpods-uuid-that-is-not-connected-right-now")
        SettingsStore.save(settings, to: defaults)
        // No presence validation at load: launching with the AirPods in their case must not
        // forget the pick. Resolution at stream start handles absence.
        #expect(SettingsStore.load(from: defaults).microphonePreference
            == .device(id: "airpods-uuid-that-is-not-connected-right-now"))

        // None round-trips as both keys absent, not as an empty string.
        settings.microphonePreference = .none
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.object(forKey: "microphoneID") == nil)
        #expect(defaults.object(forKey: "microphoneAutomatic") == nil)
        #expect(SettingsStore.load(from: defaults).microphonePreference == .none)
    }

    @Test func appPickPersistsAndSurvivesTheAppBeingClosed() {
        // M7-T2: like the mic — no running-app validation at load; the pick outlives the app's
        // process. Entire-screen round-trips as the key being absent, not an empty string.
        let defaults = makeDefaults().defaults
        var settings = makeSettings()
        settings.captureAppBundleID = "com.example.notrunning"
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.string(forKey: "captureAppBundleID") == "com.example.notrunning")
        #expect(SettingsStore.load(from: defaults).captureAppBundleID == "com.example.notrunning")

        settings.captureAppBundleID = nil
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.object(forKey: "captureAppBundleID") == nil)
        #expect(SettingsStore.load(from: defaults).captureAppBundleID == nil)
    }

    @Test func anEmptyAppBundleIDLoadsAsEntireScreen() {
        // One `defaults write` away: an empty string must not become an app filter that can
        // never resolve.
        let defaults = makeDefaults().defaults
        defaults.set("", forKey: SettingsStore.Key.captureAppBundleID)
        #expect(SettingsStore.load(from: defaults).captureAppBundleID == nil)
    }

    @Test func regionPickPersistsAndSurvivesItsDisplayBeingAway() {
        // M11-T2: like the app pick — the region round-trips (display id + rect) and outlives its
        // display; a vanished display fails loud at start (M11-T1), not at load.
        let defaults = makeDefaults().defaults
        var settings = makeSettings()
        let region = RegionSelection(displayID: 7, rect: CGRect(x: 40, y: 60, width: 800, height: 500))
        settings.captureRegion = region
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).captureRegion == region)

        settings.captureRegion = nil
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.object(forKey: "captureRegion") == nil)
        #expect(SettingsStore.load(from: defaults).captureRegion == nil)
    }

    @Test func aRegionWithNoDisplayIdRoundTripsAsMain() {
        let defaults = makeDefaults().defaults
        var settings = makeSettings()
        settings.captureRegion = RegionSelection(
            displayID: nil, rect: CGRect(x: 0, y: 0, width: 640, height: 400))
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).captureRegion?.displayID == nil)
    }

    @Test func aMalformedRegionLoadsAsNoRegion() {
        // A hand-edited or partial plist entry falls back to no region rather than a degenerate
        // one that would fail every capture.
        for bad in [
            ["x": 40.0, "y": 60.0, "width": 800.0],                       // missing height
            ["x": 40.0, "y": 60.0, "width": 0.0, "height": 500.0],        // zero width
            ["x": 40.0, "y": 60.0, "width": 800.0, "height": -1.0],       // negative height
            ["x": Double.nan, "y": 60.0, "width": 800.0, "height": 500.0],// non-finite
            ["x": 40.0, "y": 60.0, "width": 800.0, "height": 500.0, "display": Int(-3)], // negative id
            ["x": 40.0, "y": 60.0, "width": 800.0, "height": 500.0, "display": 9_999_999_999], // id > UInt32.max
        ] as [[String: Any]] {
            let defaults = makeDefaults().defaults
            defaults.set(bad, forKey: SettingsStore.Key.captureRegion)
            #expect(SettingsStore.load(from: defaults).captureRegion == nil)
        }
    }

    // MARK: - Adjusting a region pick (M18-T5)

    @Test func theFlipIsItsOwnInverseSoAPickCanBeReopened() {
        // Seeding the overlay converts the stored SCK rect back to view points with the same
        // function the confirm path uses. If that ever stopped round-tripping, a re-opened pick
        // would appear somewhere other than where it records.
        let height: CGFloat = 1285
        for rect in [CGRect(x: 40, y: 60, width: 800, height: 500),
                     CGRect(x: 0, y: 0, width: 1285, height: 1285)] {
            let there = RegionSelection.sckRect(fromViewRect: rect, displayHeightPoints: height)
            #expect(RegionSelection.sckRect(fromViewRect: there, displayHeightPoints: height) == rect)
        }
    }

    @Test func nudgingMovesWithoutResizingAndStopsAtTheEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
        let moved = RegionSelection.nudged(rect, dx: 10, dy: -5, in: screen)
        #expect(moved == CGRect(x: 110, y: 95, width: 200, height: 150))   // size untouched

        // Clamped whole: a nudge at the edge stops rather than pushing the rect off-screen.
        let atEdge = RegionSelection.nudged(
            CGRect(x: 800, y: 0, width: 200, height: 150), dx: 50, dy: -50, in: screen)
        #expect(atEdge == CGRect(x: 800, y: 0, width: 200, height: 150))
    }

    @Test func resizingMovesTheFarEdgeAndKeepsARecordableSize() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
        // The origin stays put, so the corner the user is watching is the one that moves.
        #expect(RegionSelection.resized(rect, dx: 10, dy: 10, in: screen)
            == CGRect(x: 100, y: 100, width: 210, height: 160))
        // Never below the floor that would make the pick unrecordable (M11-T1)…
        let tiny = RegionSelection.resized(rect, dx: -500, dy: -500, in: screen)
        #expect(tiny.width == RegionSelection.minimumSide)
        #expect(tiny.height == RegionSelection.minimumSide)
        // …and never past the display's edge.
        let huge = RegionSelection.resized(rect, dx: 5000, dy: 5000, in: screen)
        #expect(huge.maxX == screen.maxX)
        #expect(huge.maxY == screen.maxY)
    }

    @Test func aDragSnapsToAStandardSizeAndSaysSo() {
        // The case the badge was added for: 1920 × 1080 px is 960 × 540 pt on a 2× display, and
        // people were missing it by a few points.
        let near = CGRect(x: 20, y: 30, width: 956, height: 543)
        let pulled = RegionSelection.snapped(near, scale: 2)
        #expect(pulled.snapped)
        #expect(pulled.rect == CGRect(x: 20, y: 30, width: 960, height: 540))   // origin kept
        #expect(RegionSelection.badgeText(
            width: pulled.rect.width, height: pulled.rect.height, scale: 2, snapped: true)
            == "960 × 540 pt · 1920 × 1080 px · snapped")
    }

    @Test func aDeliberateSizeIsLeftAlone() {
        // A magnetic snap that can't be escaped would make odd-but-intended sizes unreachable.
        let odd = CGRect(x: 0, y: 0, width: 900, height: 400)
        let pulled = RegionSelection.snapped(odd, scale: 2)
        #expect(pulled.snapped == false)
        #expect(pulled.rect == odd)
        #expect(RegionSelection.badgeText(width: 900, height: 400, scale: 2).hasSuffix("px"))
    }

    // MARK: - Region overlay badge + caveat (M12-T4)

    @Test func badgeTextShowsPointsAndPixels() {
        // The power-user case: 960×540 pt on a 2× display is exactly 1920×1080 px.
        #expect(RegionSelection.badgeText(width: 960, height: 540, scale: 2)
            == "960 × 540 pt · 1920 × 1080 px")
        // A 1× display: pixels equal points.
        #expect(RegionSelection.badgeText(width: 800, height: 500, scale: 1)
            == "800 × 500 pt · 800 × 500 px")
        // Fractional drag points round independently for each unit.
        #expect(RegionSelection.badgeText(width: 100.4, height: 50.6, scale: 2)
            == "100 × 51 pt · 201 × 101 px")
    }

    @Test func mainDisplayCaveatShowsOnlyWithMoreThanOneDisplay() {
        #expect(RegionSelection.mainDisplayHint(displayCount: 1) == nil)
        #expect(RegionSelection.mainDisplayHint(displayCount: 2) == "Region capture uses the main display only")
        #expect(RegionSelection.mainDisplayHint(displayCount: 3) != nil)
    }

    @Test func automaticMicrophonePersistsAndWinsOverAStoredDevice() {
        // M6-T13: Automatic is a distinct persisted value (a bool key), and it takes precedence
        // over any device id left in the plist.
        let defaults = makeDefaults().defaults
        var settings = makeSettings()
        settings.microphonePreference = .automatic
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.bool(forKey: "microphoneAutomatic"))
        #expect(defaults.object(forKey: "microphoneID") == nil)   // no stale device left behind
        #expect(SettingsStore.load(from: defaults).microphonePreference == .automatic)

        // A hand-edited plist with both set still resolves to Automatic.
        defaults.set("some-device", forKey: "microphoneID")
        #expect(SettingsStore.load(from: defaults).microphonePreference == .automatic)
    }

    @Test func hotkeyPersistsAsTheDocumentedDict() {
        // docs/06: Dict of keyCode Int + modifiers Int, readable in `defaults read`.
        let defaults = makeDefaults().defaults
        SettingsStore.save(.standard, to: defaults)
        let dict = defaults.dictionary(forKey: "replayHotkey")
        #expect(dict?["keyCode"] as? Int == 15)
        #expect(dict?["modifiers"] as? Int == 2048 | 256)
    }

    // MARK: - Round trip

    @Test func survivesASaveAndLoad() {
        let defaults = makeDefaults().defaults
        var saved = makeSettings(
            outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            quality: .efficient, frameRateCap: 30)
        saved.replayArmed = true
        saved.replaySeconds = 120
        saved.replayHotkey = Hotkey(keyCode: 1, modifiers: 256)
        SettingsStore.save(saved, to: defaults)
        let loaded = SettingsStore.load(from: defaults)
        #expect(loaded.quality == .efficient)
        #expect(loaded.frameRateCap == 30)
        #expect(loaded.outputDirectory.path == saved.outputDirectory.path)
        #expect(loaded.replayArmed)
        #expect(loaded.replaySeconds == 120)
        #expect(loaded.replayHotkey == Hotkey(keyCode: 1, modifiers: 256))
    }

    @Test func emptyDefaultsYieldTheDefaults() {
        let loaded = SettingsStore.load(from: makeDefaults().defaults)
        #expect(loaded.quality == .balanced)
        #expect(loaded.frameRateCap == 60)
        #expect(loaded.outputDirectory == OutputLocation.defaultDirectory())
        #expect(!loaded.replayArmed)
        #expect(loaded.replaySeconds == 60)
        #expect(loaded.replayHotkey == .standard)
        #expect(loaded.showsMenuBarTimer)               // absent ⇒ on (M9-T3, opt-out)
    }

    @Test func theRecordHotkeyIsOptInAndRoundTrips() {
        // M9-T4: absent ⇒ off; a set combo persists as the documented dict and clears to key-absent.
        let defaults = makeDefaults().defaults
        #expect(SettingsStore.load(from: defaults).recordHotkey == nil)

        var settings = makeSettings()
        settings.recordHotkey = Hotkey(keyCode: 1, modifiers: 2048 | 256)
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.dictionary(forKey: "recordHotkey")?["keyCode"] as? Int == 1)
        #expect(SettingsStore.load(from: defaults).recordHotkey == Hotkey(keyCode: 1, modifiers: 2048 | 256))

        settings.recordHotkey = nil
        SettingsStore.save(settings, to: defaults)
        #expect(defaults.object(forKey: "recordHotkey") == nil)         // cleared ⇒ key removed
        #expect(SettingsStore.load(from: defaults).recordHotkey == nil)
    }

    @Test func aMalformedRecordHotkeyLoadsAsOff() {
        // Like the replay key, but nil (off) rather than a fallback combo.
        let defaults = makeDefaults().defaults
        defaults.set(["keyCode": 1], forKey: "recordHotkey")            // no modifiers
        #expect(SettingsStore.load(from: defaults).recordHotkey == nil)
    }

    @Test func theMenuBarTimerIsOptOutAndRoundTrips() {
        let defaults = makeDefaults().defaults
        // Absent stays on; an explicit false is the only thing that turns it off.
        #expect(SettingsStore.load(from: defaults).showsMenuBarTimer)
        var settings = makeSettings()
        settings.showsMenuBarTimer = false
        SettingsStore.save(settings, to: defaults)
        #expect(!SettingsStore.load(from: defaults).showsMenuBarTimer)
    }

    // MARK: - The values a plist can actually contain

    @Test(arguments: ["", "ludicrous", "BALANCED", "0"])
    func anUnreadablePresetFallsBackRatherThanRefusingToLaunch(raw: String) {
        // Hand-edited plist, or a value from a future version this build can't represent.
        let defaults = makeDefaults().defaults
        defaults.set(raw, forKey: "qualityPreset")
        #expect(SettingsStore.load(from: defaults).quality == .balanced)
    }

    @Test(arguments: [0, -1, 1, 24, 45, 120, 999])
    func onlyTheTwoDocumentedFrameRatesAreAccepted(fps: Int) {
        // `integer(forKey:)` returns 0 for absent *and* for garbage, and 0 fps divides by zero
        // downstream — so anything but 30/60 has to fall back rather than be clamped into a
        // value the user never chose.
        let defaults = makeDefaults().defaults
        defaults.set(fps, forKey: "fpsCap")
        #expect(SettingsStore.load(from: defaults).frameRateCap == 60)
    }

    @Test(arguments: [30, 60])
    func theTwoDocumentedFrameRatesSurvive(fps: Int) {
        let defaults = makeDefaults().defaults
        defaults.set(fps, forKey: "fpsCap")
        #expect(SettingsStore.load(from: defaults).frameRateCap == fps)
    }

    @Test(arguments: [0, -1])
    func nonPositiveReplaySecondsFallBackTo60(seconds: Int) {
        // `integer(forKey:)` is 0 for absent and garbage alike; never a 0-length ring (M9-T8).
        let defaults = makeDefaults().defaults
        defaults.set(seconds, forKey: "replaySeconds")
        #expect(SettingsStore.load(from: defaults).replaySeconds == 60)
    }

    @Test(arguments: [5, 30, 60, 120, 137, 900])
    func anInRangeReplayLengthSurvives(seconds: Int) {
        // M9-T8: any second-value in 5…900 is now valid, not just the old three.
        let defaults = makeDefaults().defaults
        defaults.set(seconds, forKey: "replaySeconds")
        #expect(SettingsStore.load(from: defaults).replaySeconds == seconds)
    }

    @Test func aPositiveOutOfRangeReplayLengthClampsToTheNearestBound() {
        // A hand-edited plist, or a value from a future build: clamp rather than discard the intent.
        let defaults = makeDefaults().defaults
        defaults.set(1000, forKey: "replaySeconds")
        #expect(SettingsStore.load(from: defaults).replaySeconds == 900)   // to the max
        defaults.set(3, forKey: "replaySeconds")
        #expect(SettingsStore.load(from: defaults).replaySeconds == 5)     // to the floor
    }

    @Test func gifCapsRoundTrip() {
        let defaults = makeDefaults().defaults
        var settings = Settings.standard
        settings.gifFPS = 20
        settings.gifWidth = 640
        settings.gifMaxSeconds = 15
        SettingsStore.save(settings, to: defaults)
        let loaded = SettingsStore.load(from: defaults)
        #expect(loaded.gifFPS == 20)
        #expect(loaded.gifWidth == 640)
        #expect(loaded.gifMaxSeconds == 15)
    }

    @Test func gifCapsDefaultWhenAbsentAndSnapToTheNearestChoice() {
        let defaults = makeDefaults().defaults
        let empty = SettingsStore.load(from: defaults)
        #expect(empty.gifFPS == 15)
        #expect(empty.gifWidth == 480)
        #expect(empty.gifMaxSeconds == 30)

        // A hand-edited/future value snaps to the nearest picker choice (tie → the lower).
        defaults.set(18, forKey: "gifFPS")           // → 20
        defaults.set(500, forKey: "gifWidth")        // → 480
        defaults.set(45, forKey: "gifMaxSeconds")    // → 30 (|45−30| == |45−60|, tie → 30)
        let snapped = SettingsStore.load(from: defaults)
        #expect(snapped.gifFPS == 20)
        #expect(snapped.gifWidth == 480)
        #expect(snapped.gifMaxSeconds == 30)
    }

    @Test func theMP4WidthDefaultsRoundTripsAndSnaps() {
        let (defaults, _) = makeDefaults()
        // Absent ⇒ 1920, the size every export produced before this was a setting (M18-T2).
        #expect(SettingsStore.load(from: defaults).mp4Width == 1920)

        var settings = Settings.standard
        settings.mp4Width = Settings.mp4CeilingWidth
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).mp4Width == Settings.mp4CeilingWidth)

        defaults.set(2000, forKey: "mp4Width")   // → 1920
        #expect(SettingsStore.load(from: defaults).mp4Width == 1920)
        // A 1280 stored before M19-T4 dropped that row: it never produced a smaller file than
        // 1920, so snapping up loses nothing.
        defaults.set(1280, forKey: "mp4Width")
        #expect(SettingsStore.load(from: defaults).mp4Width == 1920)
        defaults.set(99_999, forKey: "mp4Width")  // above the list → the ceiling
        #expect(SettingsStore.load(from: defaults).mp4Width == Settings.mp4CeilingWidth)
        defaults.set(0, forKey: "mp4Width")       // absent/garbage keeps the default
        #expect(SettingsStore.load(from: defaults).mp4Width == 1920)
    }

    @Test func stopAfterMinutesKeepsAStoredZeroAndSnaps() {
        // 0 is a real value here (off), not the "absent or garbage" sentinel the other picks use —
        // a stored Off must survive a relaunch (M18-T4).
        let (defaults, _) = makeDefaults()
        #expect(SettingsStore.load(from: defaults).stopAfterMinutes == 0)

        var settings = Settings.standard
        settings.stopAfterMinutes = 30
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).stopAfterMinutes == 30)

        settings.stopAfterMinutes = 0
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).stopAfterMinutes == 0)

        // A hand-written `defaults write domain key 5` stores a *string* — the loader has to read
        // it like every other pick does, not reject it into the default.
        defaults.set("30", forKey: "stopAfterMinutes")
        #expect(SettingsStore.load(from: defaults).stopAfterMinutes == 30)

        defaults.set(20, forKey: "stopAfterMinutes")     // → 15 (tie → lower)
        #expect(SettingsStore.load(from: defaults).stopAfterMinutes == 15)
        defaults.set(-5, forKey: "stopAfterMinutes")     // nonsense keeps the default
        #expect(SettingsStore.load(from: defaults).stopAfterMinutes == 0)
    }

    @Test(arguments: [0, -1])
    func nonPositiveGifCapsFallBackToTheDefaults(value: Int) {
        // `integer(forKey:)` is 0 for absent and garbage alike (the `rawGif* > 0` guard).
        let defaults = makeDefaults().defaults
        for key in ["gifFPS", "gifWidth", "gifMaxSeconds"] { defaults.set(value, forKey: key) }
        let loaded = SettingsStore.load(from: defaults)
        #expect(loaded.gifFPS == 15)
        #expect(loaded.gifWidth == 480)
        #expect(loaded.gifMaxSeconds == 30)
    }

    @Test func farOutOfRangeGifCapsSnapToTheNearestBound() {
        let defaults = makeDefaults().defaults
        defaults.set(1, forKey: "gifFPS")            // below the list → 12
        defaults.set(9999, forKey: "gifWidth")       // above the list → 800
        defaults.set(9999, forKey: "gifMaxSeconds")  // above the list → 60
        let loaded = SettingsStore.load(from: defaults)
        #expect(loaded.gifFPS == 12)
        #expect(loaded.gifWidth == 800)
        #expect(loaded.gifMaxSeconds == 60)
    }

    @Test func replayBufferLabelFormatsAsMinutesSeconds() {
        #expect(Settings.replayBufferLabel(5) == "0:05")
        #expect(Settings.replayBufferLabel(90) == "1:30")
        #expect(Settings.replayBufferLabel(200) == "3:20")
        #expect(Settings.replayBufferLabel(900) == "15:00")
    }

    @Test func parseReplayBufferHandlesBothFormsClampsAndRejectsGarbage() {
        #expect(Settings.parseReplayBuffer("3:20") == 200)     // M:SS
        #expect(Settings.parseReplayBuffer("200") == 200)      // plain seconds
        #expect(Settings.parseReplayBuffer("15:00") == 900)
        #expect(Settings.parseReplayBuffer(" 1:30 ") == 90)    // trims whitespace
        #expect(Settings.parseReplayBuffer("0:03") == 5)       // clamps up to the floor
        #expect(Settings.parseReplayBuffer("99:00") == 900)    // clamps to the max
        #expect(Settings.parseReplayBuffer("abc") == nil)      // unparseable ⇒ revert
        #expect(Settings.parseReplayBuffer("3:75") == nil)     // seconds field must be < 60
        #expect(Settings.parseReplayBuffer("") == nil)
    }

    @Test func aMalformedHotkeyFallsBackWhole() {
        // Half a shortcut is not a shortcut, and zero modifiers would fire on plain typing.
        let defaults = makeDefaults().defaults
        defaults.set(["keyCode": 15], forKey: "replayHotkey")                       // no modifiers
        #expect(SettingsStore.load(from: defaults).replayHotkey == .standard)
        defaults.set(["keyCode": 15, "modifiers": 0], forKey: "replayHotkey")       // bare key
        #expect(SettingsStore.load(from: defaults).replayHotkey == .standard)
        defaults.set(["keyCode": -2, "modifiers": 256], forKey: "replayHotkey")     // junk code
        #expect(SettingsStore.load(from: defaults).replayHotkey == .standard)
        defaults.set("⌥⌘R", forKey: "replayHotkey")                                 // wrong type
        #expect(SettingsStore.load(from: defaults).replayHotkey == .standard)
    }

    @Test func aFolderThatHasGoneAwayFallsBackToMovies() {
        // The realistic one: an external drive that was mounted when they chose it. Keeping the
        // dead path would poison every recording with SCK's opaque "invalid parameter" (02 §2).
        let defaults = makeDefaults().defaults
        defaults.set("/Volumes/GoneForever/Recordings", forKey: "outputDirectory")
        #expect(SettingsStore.load(from: defaults).outputDirectory == OutputLocation.defaultDirectory())
    }

    @Test func aFileWhereAFolderShouldBeIsNotAnOutputFolder() {
        let defaults = makeDefaults().defaults
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        defaults.set(file.path, forKey: "outputDirectory")
        #expect(SettingsStore.load(from: defaults).outputDirectory == OutputLocation.defaultDirectory())
    }

    @Test func anEmptyPathFallsBack() {
        let defaults = makeDefaults().defaults
        defaults.set("", forKey: "outputDirectory")
        #expect(SettingsStore.load(from: defaults).outputDirectory == OutputLocation.defaultDirectory())
    }

    // MARK: - AppState wiring

    @MainActor
    @Test func appStateLoadsAtLaunchAndSavesOnChange() {
        let defaults = makeDefaults().defaults
        defaults.set("high", forKey: "qualityPreset")
        defaults.set(30, forKey: "fpsCap")

        let state = AppState(defaults: defaults)
        #expect(state.quality == .high)              // read at launch…
        #expect(state.frameRateCap == 30)

        state.quality = .efficient
        #expect(defaults.string(forKey: "qualityPreset") == "efficient")   // …written on change

        // The bug this closes: a setting that persists beautifully and never reaches the
        // capture. `frameRateCap` had exactly that shape until it was threaded through here.
        state.frameRateCap = 60
        #expect(state.captureConfiguration.frameRateCap == 60)
        #expect(state.captureConfiguration.quality == .efficient)
    }

    @Test func aWindowPickRoundTripsWithItsOwner() {
        let defaults = TestDefaults.make("settings-window")
        var settings = Settings.standard
        settings.captureWindow = WindowSelection(id: 37, bundleID: "com.apple.finder")
        SettingsStore.save(settings, to: defaults)
        #expect(SettingsStore.load(from: defaults).captureWindow == settings.captureWindow)
    }

    @Test func aWindowPickStoresNothingButItsIdentity() {
        // A window title is another app's content — a private-browsing window or a DM would sit
        // in the plist in plaintext (M19-T5). Nothing but id and owner may reach disk.
        let defaults = TestDefaults.make("settings-window")
        var settings = Settings.standard
        settings.captureWindow = WindowSelection(id: 37, bundleID: "com.apple.finder")
        SettingsStore.save(settings, to: defaults)

        let stored = defaults.dictionary(forKey: SettingsStore.Key.captureWindow)
        #expect(Set(stored?.keys ?? [:].keys) == ["id", "bundleID"])
    }

    @Test func aLegacyStoredTitleIsIgnoredAndOverwritten() {
        // Entries written before M19-T5 carry a title. It must not load, and the next save of
        // anything must drop it — the whole dictionary is rewritten, so no migration is needed.
        let defaults = TestDefaults.make("settings-window")
        defaults.set(
            [SettingsStore.Key.windowID: 37,
             SettingsStore.Key.windowBundleID: "com.apple.finder",
             "title": "Private Browsing"],
            forKey: SettingsStore.Key.captureWindow)

        var settings = SettingsStore.load(from: defaults)
        #expect(settings.captureWindow == WindowSelection(id: 37, bundleID: "com.apple.finder"))

        settings.quality = .efficient
        SettingsStore.save(settings, to: defaults)
        let stored = defaults.dictionary(forKey: SettingsStore.Key.captureWindow)
        #expect(stored?["title"] == nil)
    }

    @Test func aStoredWindowPickWithoutAnOwnerIsDiscarded() {
        // It could never be verified at capture, which is the only reason to store one — keeping
        // it would mean binding a bare id (docs/02 §1c).
        let defaults = TestDefaults.make("settings-window")
        defaults.set([SettingsStore.Key.windowID: 37], forKey: SettingsStore.Key.captureWindow)
        #expect(SettingsStore.load(from: defaults).captureWindow == nil)
    }
}
