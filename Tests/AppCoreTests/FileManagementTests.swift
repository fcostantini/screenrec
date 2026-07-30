import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// Rename… and Move to Trash (M12-T2), plus the receipt that survives relaunch. These touch the
/// real filesystem — a rename is a `moveItem`, a trash a `trashItem` — so each runs against files
/// in a throwaway directory. The invariant under test: acting on a derived export never touches the
/// recording it came from.
@MainActor
@Suite struct FileManagementTests {

    private func makeDefaults() -> UserDefaults {
        TestDefaults.make()
    }

    /// A throwaway directory with the named empty files, returned for the test to act on.
    private func makeFixture(_ names: [String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }

    /// An AppState over `defaults` whose persisted receipt already points at `receipt` (the M12-T2
    /// seed path). The caller keeps `defaults` so it can inspect what a rename/trash wrote back.
    private func makeState(receipt: URL, defaults: UserDefaults) -> AppState {
        SettingsStore.saveLastExport(LastExport(url: receipt, date: Date()), to: defaults)
        return AppState(defaults: defaults)
    }

    // MARK: - The persisted receipt

    @Test func aPersistedReceiptSeedsAtLaunchWhenItsFileStillExists() throws {
        let directory = try makeFixture(["Clip.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let mp4 = directory.appendingPathComponent("Clip.mp4")

        let state = makeState(receipt: mp4, defaults: makeDefaults())
        #expect(state.lastExport?.url == mp4)
    }

    @Test func aPersistedReceiptWhoseFileVanishedDoesNotSeed() {
        let state = makeState(
            receipt: URL(fileURLWithPath: "/tmp/gone-\(UUID().uuidString).mp4"),
            defaults: makeDefaults())
        #expect(state.lastExport == nil)
    }

    // MARK: - Rename

    @Test func renameMovesTheFileRepointsTheReceiptAndLeavesTheSourceUntouched() throws {
        let directory = try makeFixture(["Recording.mov", "Recording.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Recording.mov")
        let export = directory.appendingPathComponent("Recording.mp4")

        let defaults = makeDefaults()
        let state = makeState(receipt: export, defaults: defaults)
        state.rename(export, to: "Shared demo")

        let renamed = directory.appendingPathComponent("Shared demo.mp4")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!FileManager.default.fileExists(atPath: export.path))
        #expect(state.lastExport?.url == renamed)
        #expect(SettingsStore.loadLastExport(from: defaults)?.url == renamed)
        // The invariant: renaming a derived .mp4 never touches its .mov source.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Naming a take as it stops (M21-T3)

    @Test func namingAStoppedTakeRenamesTheFileAndReportsWhereItLanded() throws {
        let directory = try makeFixture(["Recording 2026-07-29 at 16.09.44.mov"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let take = directory.appendingPathComponent("Recording 2026-07-29 at 16.09.44.mov")

        let state = AppState(defaults: makeDefaults())
        state.namesTakeOnStop = true
        var asked: (url: URL, duration: TimeInterval)?
        state.promptForTakeName = { url, duration in
            asked = (url, duration)
            return "Bug-1204 repro"
        }

        let landed = state.nameTakeIfAsked(take, duration: 15)

        #expect(asked?.url == take)
        #expect(asked?.duration == 15)      // the prompt can label the take without opening it
        #expect(landed == directory.appendingPathComponent("Bug-1204 repro.mov"))
        #expect(FileManager.default.fileExists(atPath: landed?.path ?? ""))
        #expect(!FileManager.default.fileExists(atPath: take.path))
    }

    @Test func aDeclinedPromptKeepsTheDateName() throws {
        let directory = try makeFixture(["Recording 2026-07-29 at 16.09.44.mov"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let take = directory.appendingPathComponent("Recording 2026-07-29 at 16.09.44.mov")

        let state = AppState(defaults: makeDefaults())
        state.namesTakeOnStop = true
        state.promptForTakeName = { _, _ in nil }   // Esc / Cancel

        #expect(state.nameTakeIfAsked(take, duration: 15) == nil)
        #expect(FileManager.default.fileExists(atPath: take.path))
    }

    @Test func aTakeIsNeverAskedAboutWhenTheSettingIsOff() throws {
        let directory = try makeFixture(["Recording 2026-07-29 at 16.09.44.mov"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let take = directory.appendingPathComponent("Recording 2026-07-29 at 16.09.44.mov")

        let state = AppState(defaults: makeDefaults())   // the default: off
        var asked = false
        state.promptForTakeName = { _, _ in asked = true; return "Never" }

        #expect(state.nameTakeIfAsked(take, duration: 15) == nil)
        #expect(!asked)
        #expect(FileManager.default.fileExists(atPath: take.path))
    }

    @Test func theNamePromptSettingSurvivesRelaunch() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)
        #expect(!state.namesTakeOnStop)     // off unless asked for
        state.namesTakeOnStop = true
        #expect(AppState(defaults: defaults).namesTakeOnStop)
    }

    @Test func renameResolvesACollisionRatherThanOverwriting() throws {
        let directory = try makeFixture(["a.mp4", "b.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = directory.appendingPathComponent("a.mp4")

        let state = AppState(defaults: makeDefaults())
        state.rename(a, to: "b")   // "b.mp4" is taken

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("b 2.mp4").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("b.mp4").path))
        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    @Test func renameToABlankNameIsANoOp() throws {
        let directory = try makeFixture(["Clip.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = directory.appendingPathComponent("Clip.mp4")

        let state = AppState(defaults: makeDefaults())
        state.rename(clip, to: "   ")
        #expect(FileManager.default.fileExists(atPath: clip.path))
    }

    @Test func aCaseOnlyRenameLandsExactlyRatherThanGettingSuffixed() throws {
        // On a case-insensitive volume the still-present source must not read as a collision with
        // itself: `Clip` → `clip` should land `clip.mp4`, never `clip 2.mp4`.
        let directory = try makeFixture(["Clip.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = AppState(defaults: makeDefaults())
        state.rename(directory.appendingPathComponent("Clip.mp4"), to: "clip")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("clip.mp4").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("clip 2.mp4").path))
    }

    @Test func renamePreservesTheExportReceiptDate() throws {
        // The anti-squat invariant (M12-T3): renaming keeps the original export time, so a renamed
        // old receipt can't become fresh (date: Date()) and re-squat above Start.
        let directory = try makeFixture(["Old.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("Old.mp4")

        let defaults = makeDefaults()
        let exportedAt = Date(timeIntervalSince1970: 1_000_000)   // long ago, unmistakably not "now"
        SettingsStore.saveLastExport(LastExport(url: old, date: exportedAt), to: defaults)
        let state = AppState(defaults: defaults)

        state.rename(old, to: "Renamed")
        #expect(state.lastExport?.url == directory.appendingPathComponent("Renamed.mp4"))
        #expect(state.lastExport?.date == exportedAt)             // preserved, not refreshed to now
    }

    @Test func renamingADifferentFileLeavesTheReceiptUntouched() throws {
        // The `isSameFile` guard must not regress into an unconditional receipt write.
        let directory = try makeFixture(["A.mp4", "B.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let receipt = directory.appendingPathComponent("A.mp4")

        let state = makeState(receipt: receipt, defaults: makeDefaults())
        state.rename(directory.appendingPathComponent("B.mp4"), to: "B renamed")
        #expect(state.lastExport?.url == receipt)
    }

    // MARK: - Move to Trash

    @Test func trashRemovesTheFileClearsTheReceiptAndLeavesTheSourceUntouched() throws {
        let directory = try makeFixture(["Recording.mov", "Recording.mp4"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Recording.mov")
        let export = directory.appendingPathComponent("Recording.mp4")

        let defaults = makeDefaults()
        let state = makeState(receipt: export, defaults: defaults)
        state.moveToTrash(export)

        #expect(!FileManager.default.fileExists(atPath: export.path))   // now in the Trash
        #expect(state.lastExport == nil)
        #expect(SettingsStore.loadLastExport(from: defaults) == nil)
        // The invariant again: trashing the export leaves the recording it derived from.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - The replay receipt

    /// Arms an AppState with the replay spy (reused from ReplayWiringTests) and drives one save, so
    /// `lastReplay` points at `file` — the receipt whose row also carries Rename…/Move to Trash.
    private func stateWithSavedReplay(at file: URL) async -> AppState {
        let spy = ReplayWiringTests.ReplaySpy()
        let state = AppState(defaults: makeDefaults(), replayController: spy)
        state.notifier = { _ in }
        state.isReplayArmed = true
        spy.saveResult = .success(ReplayMuxer.SavedReplay(url: file, duration: 30))
        state.saveReplay()
        await Task.yield()
        return state
    }

    @Test func renameRepointsAReplayReceiptAndKeepsItsLength() async throws {
        let directory = try makeFixture(["Replay.mov"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let replay = directory.appendingPathComponent("Replay.mov")

        let state = await stateWithSavedReplay(at: replay)
        #expect(state.lastReplay?.url == replay)              // precondition

        state.rename(replay, to: "Kept replay")
        #expect(state.lastReplay?.url == directory.appendingPathComponent("Kept replay.mov"))
        #expect(state.lastReplay?.seconds == 30)              // the length survives the rename
    }

    @Test func trashClearsAReplayReceipt() async throws {
        let directory = try makeFixture(["Replay.mov"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let replay = directory.appendingPathComponent("Replay.mov")

        let state = await stateWithSavedReplay(at: replay)
        #expect(state.lastReplay != nil)                      // precondition

        state.moveToTrash(replay)
        #expect(state.lastReplay == nil)
    }
}
