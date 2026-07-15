import Foundation

/// Where recordings are written, plus the naming and collision rules.
///
/// The naming and collision logic is pure (injected `exists` predicate), so it is testable
/// without touching disk; `preflight` and `newRecordingURL` touch the real filesystem.
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

    /// e.g. `2026-07-14 at 10.12.34` — POSIX locale, caller's time zone (injectable so tests
    /// are deterministic regardless of the machine's zone).
    static func timestamp(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }

    /// First non-colliding file name, appending ` 2`, ` 3`, … before the extension (docs/02 §6).
    /// `exists` is injected so the policy is testable without disk I/O.
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

    /// An unwritable output directory surfaces later as an opaque SCK/AVFoundation "invalid
    /// parameter" (docs/02 §2); catch it here. Probes *write* access rather than `opendir`,
    /// which only proves read/execute.
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
    /// Check-then-act, so display only (the dry-run); real recording uses `reserveRecordingURL`.
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

    public enum ReservationError: Error, Equatable {
        /// Creating the placeholder failed for a reason other than a name collision
        /// (e.g. the directory is unwritable). `code` is the POSIX errno.
        case cannotCreate(path: String, code: Int32)
        /// An explicit user-specified output path already exists (we won't overwrite it).
        case alreadyExists(path: String)
    }

    /// `O_EXCL`-creates an empty placeholder at `url`; true if it claimed the name, false if
    /// taken. Retries `EINTR`, throws otherwise. The placeholder is **kept**: the writer removes
    /// it as it creates the real file, so the name is held throughout, never freed in between.
    private static func claim(_ url: URL) throws -> Bool {
        while true {
            let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if descriptor >= 0 { close(descriptor); return true }
            switch errno {
            case EEXIST: return false
            case EINTR: continue
            default: throw ReservationError.cannotCreate(path: url.path, code: errno)
            }
        }
    }

    /// Atomically reserves the first non-colliding auto-named recording URL, so two recordings
    /// started in the same second get different names (`… 2.mov`).
    public func reserveRecordingURL(
        prefix: String = "Recording",
        ext: String = "mov",
        date: Date,
        timeZone: TimeZone = .current
    ) throws -> URL {
        let base = "\(prefix) \(Self.timestamp(for: date, timeZone: timeZone))"
        var suffix = 1
        while true {
            let name = suffix == 1 ? "\(base).\(ext)" : "\(base) \(suffix).\(ext)"
            let url = directory.appendingPathComponent(name)
            if try Self.claim(url) { return url }
            suffix += 1
        }
    }

    /// Reserves an exact, user-specified output path (the `record` positional argument).
    /// Throws `.alreadyExists` instead of overwriting a file that's already there.
    public static func reserveExact(_ url: URL) throws -> URL {
        guard try claim(url) else { throw ReservationError.alreadyExists(path: url.path) }
        return url
    }
}
