import Foundation

/// Where recordings are written, plus the naming and collision rules.
///
/// The naming and collision logic is pure (injected `exists` predicate) so it is
/// unit-testable without touching disk; `preflight` and `newRecordingURL` touch the
/// real filesystem.
public struct OutputLocation: Sendable {
    public let directory: URL

    public init(directory: URL = OutputLocation.defaultDirectory()) {
        self.directory = directory
    }

    /// `~/Movies` — unlike Desktop/Documents/Downloads it is not TCC-protected, so
    /// writing there never fails with the opaque "invalid parameter" error (docs/02 §2).
    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
    }

    // MARK: - Naming (pure)

    /// e.g. `2026-07-14 at 10.12.34` — POSIX locale, caller's time zone (injectable so
    /// tests are deterministic regardless of the machine's zone). Internal composition
    /// step for `newRecordingURL`; not part of the module's public surface.
    static func timestamp(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }

    /// First non-colliding file name, appending ` 2`, ` 3`, … before the extension
    /// (docs/02 §6). `exists` is injected so the policy is testable without disk I/O.
    /// Internal composition step for `newRecordingURL`.
    static func resolvedFileName(
        base: String,
        ext: String,
        exists: (String) -> Bool
    ) -> String {
        let first = "\(base).\(ext)"
        guard exists(first) else { return first }
        var suffix = 2
        while true {
            let candidate = "\(base) \(suffix).\(ext)"
            if !exists(candidate) { return candidate }
            suffix += 1
        }
    }

    // MARK: - Preflight (filesystem)

    public enum DirectoryAccess: Sendable, Equatable {
        case accessible
        case inaccessible(reason: String)
    }

    /// An output directory the process can't write to surfaces later as an opaque
    /// SCK/AVFoundation "invalid parameter"; catch it here. We probe *write* access
    /// (recording needs it) rather than `opendir` (which only proves read/execute), and
    /// distinguish a missing folder from a permission denial so the guidance is correct.
    public static func preflight(_ directory: URL) -> DirectoryAccess {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .inaccessible(reason: """
                The output folder doesn't exist: \(directory.path)
                Choose a different folder in Settings.
                """)
        }
        let probe = directory.appendingPathComponent(".screenrec-write-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: probe.path, contents: nil) else {
            return .inaccessible(reason: """
                Can't write to the output folder: \(directory.path)
                If this is Desktop, Documents, or Downloads, grant Files and Folders access in \
                System Settings → Privacy & Security. The default folder (~/Movies) needs no grant.
                """)
        }
        try? fileManager.removeItem(at: probe)
        return .accessible
    }

    // MARK: - Compose

    /// Full URL for a new recording, resolving collisions against the real filesystem.
    /// Collision resolution here is check-then-act; the writer (M2) creates the file
    /// with `O_EXCL` to close the same-instant race for good (see STATUS field notes).
    public func newRecordingURL(
        prefix: String = "Recording",
        ext: String = "mov",
        date: Date,
        timeZone: TimeZone = .current
    ) -> URL {
        let base = "\(prefix) \(Self.timestamp(for: date, timeZone: timeZone))"
        let name = Self.resolvedFileName(base: base, ext: ext) { candidate in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path)
        }
        return directory.appendingPathComponent(name)
    }
}
