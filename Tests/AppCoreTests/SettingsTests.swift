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
        let suite = "screenrec-tests-\(UUID().uuidString)"
        // Invariant: a fresh UUID suite name is always a valid, unused domain.
        return (UserDefaults(suiteName: suite)!, suite)
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
        #expect(SettingsStore.Key.replayArmed == "replayArmed")
        #expect(SettingsStore.Key.replaySeconds == "replaySeconds")
        #expect(SettingsStore.Key.replayHotkey == "replayHotkey")
        #expect(SettingsStore.Key.recordHotkey == "recordHotkey")
        #expect(SettingsStore.Key.hotkeyKeyCode == "keyCode")
        #expect(SettingsStore.Key.hotkeyModifiers == "modifiers")
        #expect(SettingsStore.Key.showsMenuBarTimer == "showsMenuBarTimer")
    }

    @Test func savesUnderExactlyThoseKeysAndNoOthers() {
        // `defaults read` is how docs/03's verify inspects this, so what lands in our domain has
        // to be the documented keys and nothing else — no @AppStorage prefix, no stray extras.
        let (defaults, suite) = makeDefaults()
        SettingsStore.save(.standard, to: defaults)
        let written = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(written.keys) == [
            "outputDirectory", "qualityPreset", "fpsCap",
            "replayArmed", "replaySeconds", "replayHotkey", "showsMenuBarTimer",
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

    @Test func replayBufferLabelFormatsAsMinutesSeconds() {
        #expect(Settings.replayBufferLabel(5) == "0:05")
        #expect(Settings.replayBufferLabel(90) == "1:30")
        #expect(Settings.replayBufferLabel(200) == "3:20")
        #expect(Settings.replayBufferLabel(900) == "15:00")
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
}
