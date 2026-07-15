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

    @Test func keyNamesMatchTheSpecExactly() {
        // docs/06 calls these contractual and says do not rename. They're spelled once in
        // SettingsStore.Key; this is the assertion that ties that spelling to the document —
        // a typo here would surface a milestone later, in a task that assumes it's at fault.
        #expect(SettingsStore.Key.outputDirectory == "outputDirectory")
        #expect(SettingsStore.Key.qualityPreset == "qualityPreset")
        #expect(SettingsStore.Key.fpsCap == "fpsCap")
    }

    @Test func savesUnderExactlyThoseKeysAndNoOthers() {
        // `defaults read` is how docs/03's verify inspects this, so what lands in our domain has
        // to be the documented keys and nothing else — no @AppStorage prefix, no stray extras.
        let (defaults, suite) = makeDefaults()
        SettingsStore.save(.standard, to: defaults)
        let written = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(written.keys) == ["outputDirectory", "qualityPreset", "fpsCap"])
    }

    @Test func qualityPersistsAsItsDocumentedString() {
        // docs/06: `efficient`|`balanced`|`high` — human-readable in `defaults read`, and the
        // literal M5 would have to match. An enum ordinal would be neither.
        let defaults = makeDefaults().defaults
        SettingsStore.save(
            Settings(outputDirectory: URL(fileURLWithPath: "/tmp"), quality: .high,
                     frameRateCap: 30),
            to: defaults)
        #expect(defaults.string(forKey: "qualityPreset") == "high")
        #expect(defaults.integer(forKey: "fpsCap") == 30)
    }

    @Test func outputDirectoryPersistsAsAPathNotAnArchivedURL() {
        // docs/06 says String. A URL would archive as opaque data that `defaults read` can't
        // show a human — and the verify step is a human reading `defaults read`.
        let defaults = makeDefaults().defaults
        SettingsStore.save(
            Settings(outputDirectory: URL(fileURLWithPath: "/tmp"), quality: .balanced,
                     frameRateCap: 60),
            to: defaults)
        #expect(defaults.string(forKey: "outputDirectory") == "/tmp")
    }

    // MARK: - Round trip

    @Test func survivesASaveAndLoad() {
        let defaults = makeDefaults().defaults
        let saved = Settings(
            outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            quality: .efficient, frameRateCap: 30)
        SettingsStore.save(saved, to: defaults)
        let loaded = SettingsStore.load(from: defaults)
        #expect(loaded.quality == .efficient)
        #expect(loaded.frameRateCap == 30)
        #expect(loaded.outputDirectory.path == saved.outputDirectory.path)
    }

    @Test func emptyDefaultsYieldTheDefaults() {
        let loaded = SettingsStore.load(from: makeDefaults().defaults)
        #expect(loaded.quality == .balanced)
        #expect(loaded.frameRateCap == 60)
        #expect(loaded.outputDirectory == OutputLocation.defaultDirectory())
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
