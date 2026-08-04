import AppKit
import Foundation

@testable import AppCore
@testable import AppShell

/// Carries a value out of an escaping closure. `AppCoreTests` has its own; a test target cannot
/// import another's.
final class Box<Value>: @unchecked Sendable {
    var value: Value?
}

/// Builds the real menu from a real `AppState` and flattens it — `menudriver dump`'s output,
/// produced in-process with no app running (M29-T2).
@MainActor
enum MenuSnapshot {

    static func state(directory: URL? = nil) -> AppState {
        let state = AppState(defaults: TestSuites.make())
        if let directory { state.outputDirectory = directory }
        return state
    }

    static func rows(_ state: AppState) -> [NSMenuItem] {
        MenuBuilder(state: state, windows: WindowPresenter(), thumbnails: MenuThumbnails()).rows()
    }

    /// Top-level titles, separators as `---`.
    static func titles(_ state: AppState) -> [String] {
        rows(state).map { $0.isSeparatorItem ? "---" : $0.title }
    }

    /// The first row with this title, at any depth.
    static func item(_ state: AppState, titled title: String) -> NSMenuItem? {
        find(rows(state), title)
    }

    private static func find(_ items: [NSMenuItem], _ title: String) -> NSMenuItem? {
        for item in items {
            if item.title == title { return item }
            if let submenu = item.submenu, let hit = find(submenu.items, title) { return hit }
        }
        return nil
    }

    /// A directory of empty files with chosen modification dates, for the recents rows.
    static func directory(_ files: [(name: String, daysAgo: Double)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("menu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            let url = directory.appendingPathComponent(file.name)
            try Data().write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-file.daysAgo * 86_400)],
                ofItemAtPath: url.path)
        }
        return directory
    }
}

/// Throwaway `UserDefaults` suites, swept at exit.
///
/// ⚠️ **A written-to suite is a real plist in `~/Library/Preferences`**, and one per test per run
/// accumulates without limit — `AppCoreTests`' own `TestDefaults` exists because that reached
/// 49,668 files. This target cannot import it, so it carries the same guard rather than none.
enum TestSuites {

    static func make() -> UserDefaults {
        let suite = "\(prefix)\(UUID().uuidString)"
        register(suite)
        return UserDefaults(suiteName: suite)!
    }

    private static let prefix = "AppShellTests-"
    private static let lock = NSLock()
    private static nonisolated(unsafe) var suites: [String] = []
    private static nonisolated(unsafe) var didInstallSweep = false

    /// `atexit` because swift-testing has no process-wide teardown, and a per-test one would have to
    /// be remembered by every future author — which is how this leaks in the first place.
    private static func register(_ suite: String) {
        lock.lock()
        suites.append(suite)
        let isFirst = !didInstallSweep
        didInstallSweep = true
        lock.unlock()
        guard isFirst else { return }
        sweepStale()
        atexit { TestSuites.removeAll() }
    }

    /// Leftovers from earlier runs: the exit sweep races `cfprefsd`, which owns the file and can
    /// write it back afterwards, so sweeping on the way in keeps the residue bounded to one run.
    /// The age floor keeps hands off a run happening right now.
    private static func sweepStale(olderThan minimumAge: TimeInterval = 300) {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(prefix) {
            let url = directory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(modified) > minimumAge else { continue }
            UserDefaults.standard.removePersistentDomain(
                forName: (name as NSString).deletingPathExtension)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func removeAll() {
        lock.lock()
        let names = suites
        suites.removeAll()
        lock.unlock()
        for name in names {
            UserDefaults.standard.removePersistentDomain(forName: name)
            // `removePersistentDomain` alone leaks — `cfprefsd` writes the file back on its own
            // schedule. Flush, then unlink whatever is left.
            CFPreferencesAppSynchronize(name as CFString)
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Preferences/\(name).plist"))
        }
    }
}
