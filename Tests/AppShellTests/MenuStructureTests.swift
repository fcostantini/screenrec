import AppKit
import Foundation
import RecorderCore
import Testing

@testable import AppCore
@testable import AppShell

/// The menu's structure, pinned in-process (M29-T2) — the checks M28 could only make by deploying
/// the app and driving it over Accessibility.
///
/// ⚠️ The **recording** and **paused** menus are absent on purpose: they are gated on
/// `session.isActive`, which needs a real `RecordingSession` (a `CaptureEngine` and an
/// `AVAssetWriter`). `apply(.started)` moves the status icon but not the session, so a test written
/// against it would assert the *idle* menu and pass. Those two layouts stay with the live dump.
@MainActor
@Suite struct MenuStructureTests {

    // MARK: - The idle menu

    @Test func theIdleMenuIsTheDocumentedOrder() {
        let state = MenuSnapshot.state()
        state.refreshSources(displays: [DisplayOption(id: 1, name: "Built-in", isMain: true)])

        // The header's right-hand status reads live TCC, which no test can set — so it is asserted
        // as a row, not as a verdict about a grant this machine happens to hold.
        let titles = MenuSnapshot.titles(state)
        #expect(titles.first?.hasPrefix("ScreenRec — ") == true)
        #expect(Array(titles.dropFirst()) == [
            "---",
            "Start Recording", "Arm Instant Replay", "---",
            "Source: Entire Screen", "Microphone: None", "Capture System Audio",
            "Quality: Balanced", "Stop After: Off", "---",
            "Recordings", "---",
            "Settings…", "Quit",
        ])
    }

    @Test func settingsAndQuitCarryTheirShortcuts() {
        let state = MenuSnapshot.state()
        #expect(MenuSnapshot.item(state, titled: "Settings…")?.keyEquivalent == ",")
        #expect(MenuSnapshot.item(state, titled: "Quit")?.keyEquivalent == "q")
    }

    // MARK: - Arming

    @Test func armingAddsItsCostItsCaveatAndTheSaveRowAndNothingElse() {
        let state = MenuSnapshot.state()
        let before = MenuSnapshot.titles(state)

        state.isReplayArmed = true
        let after = MenuSnapshot.titles(state)

        #expect(MenuSnapshot.item(state, titled: "Arm Instant Replay")?.state == .on)
        #expect(after.count == before.count + 3)
        let armed = after.drop { $0 != "Arm Instant Replay" }.dropFirst().prefix(3)
        #expect(Array(armed) == [
            state.replayBufferMenuLabel,
            "Notification banners may be hidden while armed",
            "Save Replay Now",
        ])
        // The cost and the caveat state something; only the save row does something.
        #expect(MenuSnapshot.item(state, titled: state.replayBufferMenuLabel)?.isEnabled == false)
        #expect(MenuSnapshot.item(state, titled: "Save Replay Now")?.isEnabled == true)
    }

    // MARK: - What is left out of a take

    @Test func anExcludedAppSaysItLosesItsPictureAsWellAsItsSound() {
        let state = MenuSnapshot.state()
        state.refreshSources(displays: [DisplayOption(id: 1, name: "Built-in", isMain: true)])
        state.refreshApps([CapturableApp(bundleID: "com.spotify.client", name: "Spotify")],
                          excluding: nil)
        state.sources.sourceChoice = .displayExcluding(bundleID: "com.spotify.client")

        #expect(MenuSnapshot.titles(state).contains("Spotify won't be seen or heard"))
        #expect(MenuSnapshot.item(state, titled: "Spotify won't be seen or heard")?.isEnabled == false)
    }

    @Test func aMutedAppKeepsItsPictureAndSaysSo() {
        let state = MenuSnapshot.state()
        state.sources.appDisplayName = { $0 == "com.spotify.client" ? "Spotify" : nil }
        state.sources.mutedAppBundleID = "com.spotify.client"

        let titles = MenuSnapshot.titles(state)
        #expect(titles.contains("Spotify will be seen but not heard"))
        // The caveat that only mute carries: a tap picks up windowless apps SCK omits (M27-T2).
        #expect(titles.contains("Sound from apps with no window is captured too"))
    }

    @Test func aPickedAppThatIsGoneStaysListedAndIsDimmed() {
        // The pick survives absence, the microphone rule — and the row dims rather than looking
        // selectable.
        let state = MenuSnapshot.state()
        state.sources.appDisplayName = { $0 == "com.acme.app" ? "Acme" : nil }
        state.sources.sourceChoice = .app(bundleID: "com.acme.app")
        state.refreshApps([], excluding: nil)

        let row = MenuSnapshot.item(state, titled: "Acme (not running)")
        #expect(row != nil)
        #expect(row?.isEnabled == false)
        #expect(row?.state == .on)          // still the pick
    }

    // MARK: - Failures and exports

    @Test func aStartThatFailedShowsItsReasonDirectlyUnderStart() {
        let state = MenuSnapshot.state()
        state.apply(.failed(message: "No displays available."))

        let titles = MenuSnapshot.titles(state)
        let start = titles.firstIndex(of: "Start Recording")
        #expect(start != nil)
        #expect(titles[start! + 1] == "No displays available.")
    }

    @Test func anExportInFlightBecomesAProgressRowCarryingItsPercentage() async {
        let state = MenuSnapshot.state()
        state.notifier = { _ in }
        let release = Box<Bool>()
        state.exports.exportFunction = { _, output, _, _, _, progress in
            progress(0.42)
            while release.value != true { await Task.yield() }
            return output
        }

        state.exportToMP4(URL(fileURLWithPath: "/tmp/Clip.mov"))
        var spins = 0
        while state.exports.exportProgress != 0.42, spins < 100_000 {
            await Task.yield()
            spins += 1
        }

        let row = MenuSnapshot.item(state, titled: "Exporting… 42%")
        #expect(row != nil)
        #expect(row?.isEnabled == false)
        #expect(row?.view is ExportProgressRowView)   // the bar, not just the words

        release.value = true
        while state.exports.exportInProgress != nil { await Task.yield() }
    }

    // MARK: - The recents rows

    @Test func anEmptyOutputFolderLeavesTheFolderRowAlone() throws {
        let directory = try MenuSnapshot.directory([])
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = MenuSnapshot.state(directory: directory)
        state.refreshRecentRecordings()

        let recordings = MenuSnapshot.item(state, titled: "Recordings")?.submenu?.items ?? []
        #expect(recordings.count == 1)
        #expect(recordings.first?.title.hasPrefix("Open Folder") == true)
    }

    @Test func recentsSitUnderTheDayTheyWereMade() throws {
        let directory = try MenuSnapshot.directory([
            ("a.mov", 0), ("b.mov", 1), ("c.mov", 1), ("d.mov", 40),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = MenuSnapshot.state(directory: directory)
        state.refreshRecentRecordings()

        let rows = MenuSnapshot.item(state, titled: "Recordings")?.submenu?.items ?? []
        let titles = rows.map { $0.isSeparatorItem ? "---" : $0.title }
        #expect(titles.contains("Today"))
        #expect(titles.contains("Yesterday"))
        // One header per day, not per file: b and c share theirs.
        #expect(titles.filter { $0 == "Yesterday" }.count == 1)
        // Headers are the inert rows — which is what tells them from the file rows interleaved
        // with them, and what stops this passing on a filename.
        let headers = rows.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title)
        #expect(headers.count == 3)
        #expect(headers.first == "Today")
        #expect(headers.dropFirst().first == "Yesterday")
        // 40 days back is past the weekday window, so it is a date rather than a name.
        #expect(headers.last != "Today" && headers.last != "Yesterday")
    }

    @Test func everyRecentRowCarriesTheWholeFileSubmenu() throws {
        let directory = try MenuSnapshot.directory([("a.mov", 0)])
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = MenuSnapshot.state(directory: directory)
        state.refreshRecentRecordings()

        let row = MenuSnapshot.item(state, titled: "a.mov")
        #expect(row?.view is RecentRowView)          // the thumbnail well (M28-T3)
        #expect(row?.submenu?.items.map(\.title).filter { !$0.isEmpty } == [
            "Reveal in Finder", "Quick Look", "Share…", "Copy",
            "Export as MP4", "Save as GIF", "Trim…",
            "Rename…", "Move to Trash",
        ])
    }

    /// M32-T3: the row exists only when there is news, and it sits with Settings/Quit rather than
    /// among the actions — it is information, not something to press.
    @Test func anAvailableUpdateAddsOneDimmedRowAboveSettings() async {
        let state = MenuSnapshot.state()
        let before = MenuSnapshot.titles(state)
        #expect(!before.contains { $0.contains("is available") })

        await state.checkForUpdate { ["v99.0.0"] }
        let after = MenuSnapshot.titles(state)
        let index = after.firstIndex(of: "99.0.0 is available")
        #expect(index != nil, "the update row is missing")
        if let index {
            // `dropFirst` rather than `after[index + 1]`: a row that moves to the very end of the
            // menu must fail this test, not crash the whole suite on an out-of-range index.
            #expect(after.dropFirst(index + 1).first == "Settings…")
        }
        #expect(after.count == before.count + 1)       // exactly one row, and nothing else moved
    }

    /// The row is a door, not a notice — a recipient handed a `.app` has no other route to a newer
    /// build. ⚠️ **Deliberately not fired here**: that would open a browser, so only the live leg
    /// proves `NSWorkspace.open`. This proves the row is enabled and carries the right destination.
    @Test func theUpdateRowOpensTheReleasesPage() async {
        let state = MenuSnapshot.state()
        await state.checkForUpdate { ["v99.0.0"] }
        let row = MenuSnapshot.item(state, titled: "99.0.0 is available")
        #expect(row?.isEnabled == true)
        #expect(row is ActionMenuItem)
        #expect(row?.representedObject as? URL == UpdateCheck.releasesPageURL)
    }
}
