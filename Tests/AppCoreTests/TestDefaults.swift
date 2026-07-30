import Foundation

/// A throwaway `UserDefaults` suite, so tests never read or scribble on the real preferences
/// (`AppState` persists on `didSet`, so a bare `AppState()` writes to `UserDefaults.standard`).
///
/// ⚠️ **The suite must be removed, not just abandoned.** A written-to suite is a real plist in
/// `~/Library/Preferences`, and one per test per run accumulates without limit — measured at
/// **49,668 files / 194 MB**, 99% of that directory, before this existed. Every name handed out
/// here is swept at process exit.
enum TestDefaults {

    /// A fresh suite nobody else is using. `label` only aids identifying a stray plist by eye.
    static func make(_ label: String = "screenrec-tests") -> UserDefaults {
        makeNamed(label).defaults
    }

    /// The suite name too, for a test that inspects that domain *alone* — the process's
    /// `dictionaryRepresentation()` also carries every inherited global, which is not what
    /// "what did we write" means.
    static func makeNamed(_ label: String = "screenrec-tests") -> (defaults: UserDefaults, suite: String) {
        let suite = "\(label)-\(UUID().uuidString)"
        register(suite)
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: - The sweep

    private static let lock = NSLock()
    private static nonisolated(unsafe) var suites: [String] = []
    private static nonisolated(unsafe) var didInstallSweep = false

    /// Records a suite for the exit sweep, installing the sweeps on first use. `atexit` because
    /// swift-testing has no process-wide teardown hook, and a per-test one would have to be
    /// remembered by every author of every future test — which is exactly how this leaked.
    private static func register(_ suite: String) {
        lock.lock()
        suites.append(suite)
        let isFirst = !didInstallSweep
        didInstallSweep = true
        lock.unlock()
        guard isFirst else { return }
        sweepStaleSuites()
        atexit { TestDefaults.removeAll() }
    }

    /// Deletes leftovers from *earlier* runs. The exit sweep races `cfprefsd`, which owns the file
    /// and may write it back after the handler runs — measured losing that race for ~150 of ~600
    /// suites, run to run. Sweeping on the way in as well makes the leak self-healing and bounded
    /// to one run's residue instead of cumulative.
    ///
    /// The age floor keeps hands off a run happening right now — this deletes only what no live
    /// process is still using.
    private static func sweepStaleSuites(olderThan minimumAge: TimeInterval = 300) {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where knownPrefixes.contains(where: name.hasPrefix) {
            let url = directory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(modified) > minimumAge else { continue }
            UserDefaults.standard.removePersistentDomain(
                forName: (name as NSString).deletingPathExtension)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Every label this file hands out. A new one must be added here or its leftovers never expire.
    private static let knownPrefixes = ["screenrec-tests-", "appstate-tests-", "settings-window-"]

    private static func removeAll() {
        lock.lock()
        let names = suites
        suites.removeAll()
        lock.unlock()
        for name in names {
            UserDefaults.standard.removePersistentDomain(forName: name)
            // ⚠️ `removePersistentDomain` alone leaks: `cfprefsd` owns the file and writes it back
            // on its own schedule, which at exit is often after we are gone (measured — 154 of ~600
            // survived a run with only the removal). Flush, then unlink what is left.
            CFPreferencesAppSynchronize(name as CFString)
            try? FileManager.default.removeItem(at: plistURL(for: name))
        }
    }

    private static func plistURL(for suite: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(suite).plist")
    }
}
