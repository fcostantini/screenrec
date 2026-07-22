import Foundation
import Testing
@testable import AppCore

/// M12-T3 "the menu tells the truth": the pure label strings the submenu titles carry, and the
/// staleness that expires a persisted export receipt.
@MainActor
@Suite struct MenuTruthTests {

    private func makeState() -> AppState {
        AppState(defaults: UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!)
    }

    // MARK: - Source label

    @Test func sourceLabelIsPlainEntireScreenWithOneDisplay() {
        let state = makeState()
        state.refreshSources(displays: [DisplayOption(id: 1, name: "Built-in", isMain: true)])
        #expect(state.sourceMenuLabel == "Entire Screen")     // no display name when there's no choice
    }

    @Test func sourceLabelNamesTheDisplayWhenThereIsAChoice() {
        let state = makeState()
        state.refreshSources(displays: [
            DisplayOption(id: 1, name: "Sidecar", isMain: false),
            DisplayOption(id: 2, name: "Built-in Retina Display", isMain: true),
        ])
        #expect(state.sourceMenuLabel == "Entire Screen (Built-in Retina Display)")
    }

    @Test func sourceLabelIsTheAppNameForAScopedPick() {
        let state = makeState()
        state.appDisplayName = { $0 == "com.acme.app" ? "Acme" : nil }
        state.sourceChoice = .app(bundleID: "com.acme.app")
        #expect(state.sourceMenuLabel == "Acme")
    }

    @Test func sourceLabelIsTheRegionSizeForARegionPick() {
        let state = makeState()
        state.setRegion(displayID: nil, rect: CGRect(x: 0, y: 0, width: 820, height: 512))
        #expect(state.sourceMenuLabel == "Region 820×512")
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
        let staleDefaults = UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!
        SettingsStore.saveLastExport(
            LastExport(url: file, date: Date(timeIntervalSinceNow: -7200)), to: staleDefaults)
        let staleState = AppState(defaults: staleDefaults)
        #expect(staleState.lastExport != nil)                 // seeded (existence only, staleness later)
        staleState.expireStaleExportReceipt()
        #expect(staleState.lastExport == nil)

        // Fresh: persisted just now → expiry keeps it.
        let freshDefaults = UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!
        SettingsStore.saveLastExport(LastExport(url: file, date: Date()), to: freshDefaults)
        let freshState = AppState(defaults: freshDefaults)
        freshState.expireStaleExportReceipt()
        #expect(freshState.lastExport?.url == file)
    }
}
