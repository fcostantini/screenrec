import AVFoundation
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

    /// An unwritable output directory surfaces later as an opaque AVFoundation permission error
    /// (docs/02 §2); catch it here. Probes with a throwaway `AVAssetWriter.startWriting()` — the
    /// exact call a recording makes — because a plain POSIX create passes on the TCC-protected
    /// folders (Desktop/Documents/Downloads) where the writer fails, so a `createFile` probe would
    /// wave them through and the recording then wedge at capture.
    public static func preflight(_ directory: URL) -> DirectoryAccess {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .inaccessible(reason: """
                The output folder doesn't exist: \(directory.path)
                Choose an existing folder.
                """)
        }
        // One input, so the probe matches a real writer: an input-less writer can be refused on
        // some runtimes, which would wrongly reject even a writable folder. `startWriting()`
        // creates the probe file; `cancelWriting()` removes it.
        let probe = directory.appendingPathComponent(".screenrec-preflight-\(UUID().uuidString).mov")
        let writer = try? AVAssetWriter(outputURL: probe, fileType: .mov)
        if let writer {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2])
            if writer.canAdd(input) { writer.add(input) }
        }
        guard let writer, writer.startWriting() else {
            try? fileManager.removeItem(at: probe)
            return .inaccessible(reason: """
                Can't write to the output folder: \(directory.path)
                If this is Desktop, Documents, or Downloads, grant Files and Folders access in \
                System Settings → Privacy & Security. The default folder (~/Movies) needs no grant.
                """)
        }
        writer.cancelWriting()
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

    public enum ReservationError: Error, Equatable, LocalizedError {
        /// Creating the placeholder failed for a reason other than a name collision
        /// (e.g. the directory is unwritable). `code` is the POSIX errno.
        case cannotCreate(path: String, code: Int32)
        /// An explicit user-specified output path already exists (we won't overwrite it).
        case alreadyExists(path: String)
        /// The path's `.partial` companion exists — an interrupted recording is in the way,
        /// and the user never typed that name, so the message must explain what it is.
        case interruptedRecordingInTheWay(path: String)

        public var errorDescription: String? {
            switch self {
            case .cannotCreate(let path, let code):
                let reason = String(cString: strerror(code))
                return "Couldn't create \"\(path)\" (\(reason)). Check that the output folder exists and is writable."
            case .alreadyExists(let path):
                return "\"\(path)\" already exists — choose a different name or move the file."
            case .interruptedRecordingInTheWay(let path):
                return "\"\(path)\" is an interrupted recording. Rename it to end in .mov to "
                    + "recover it, or delete it, then try again."
            }
        }
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
    /// started in the same second get different names (`… 2.mov`). With `asPartial` (the
    /// default) the claim is made on the name's `.partial` companion — the in-progress file —
    /// so nothing that looks finished exists until finalize renames it; replay saves pass
    /// false (they finish in well under a second, so a partial phase buys nothing).
    public func reserveRecordingURL(
        prefix: String = "Recording",
        ext: String = "mov",
        date: Date,
        timeZone: TimeZone = .current,
        asPartial: Bool = true
    ) throws -> URL {
        let base = "\(prefix) \(Self.timestamp(for: date, timeZone: timeZone))"
        var suffix = 1
        while true {
            let name = suffix == 1 ? "\(base).\(ext)" : "\(base) \(suffix).\(ext)"
            let url = directory.appendingPathComponent(name)
            if asPartial {
                if !FileManager.default.fileExists(atPath: url.path),
                   try Self.claim(Self.partialURL(for: url)) {
                    return url
                }
            } else if try Self.claim(url) {
                return url
            }
            suffix += 1
        }
    }

    /// Reserves an exact, user-specified output path (the `record` positional argument).
    /// Throws `.alreadyExists` instead of overwriting a file that's already there.
    public static func reserveExact(_ url: URL) throws -> URL {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ReservationError.alreadyExists(path: url.path)
        }
        guard try claim(partialURL(for: url)) else {
            throw ReservationError.interruptedRecordingInTheWay(path: partialURL(for: url).path)
        }
        return url
    }

    // MARK: - The .partial lifecycle

    /// The in-progress companion of a final recording URL: `… .mov` → `… .mov.partial`.
    public static func partialURL(for url: URL) -> URL {
        url.appendingPathExtension("partial")
    }

    /// Renames a finished `.partial` to its final name, resolving collisions the same way
    /// reservation does (`… 2.mov`). An extension-less intended name (CLI exact path) must
    /// not grow a trailing dot. Returns the final URL.
    public static func finalizePartial(_ partial: URL) throws -> URL {
        let intended = partial.deletingPathExtension()
        let directory = intended.deletingLastPathComponent()
        let exists = { (candidate: String) in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path)
        }
        let ext = intended.pathExtension
        let name: String
        if ext.isEmpty {
            let base = intended.lastPathComponent
            name = exists(base) ? resolvedFileName(base: base, ext: "", exists: exists) : base
        } else {
            name = resolvedFileName(
                base: intended.deletingPathExtension().lastPathComponent, ext: ext, exists: exists)
        }
        let final = directory.appendingPathComponent(name)
        try FileManager.default.moveItem(at: partial, to: final)
        return final
    }

    /// Orphaned `.partial`s are already-playable fragmented movies a crash left behind
    /// (docs/04 §3.2); recovery is a rename, not a repair. Returns the recovered final URLs.
    /// `olderThan` keeps hands off anything a live writer may own: a recording's partial is
    /// touched about once a second, so one untouched for a minute has no living owner —
    /// the in-process "no recording running" guarantee can't see other processes (the CLI).
    public func recoverOrphanedPartials(olderThan minimumAge: TimeInterval = 60) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".partial") }.compactMap { name in
            let partial = directory.appendingPathComponent(name)
            let attributes = try? FileManager.default.attributesOfItem(atPath: partial.path)
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast
            guard Date().timeIntervalSince(modified) > minimumAge else { return nil }
            // A 0-byte partial is a reservation placeholder that never became a recording —
            // nothing to recover, just litter.
            guard let size = attributes?[.size] as? Int, size > 0 else {
                try? FileManager.default.removeItem(at: partial)
                return nil
            }
            return try? Self.finalizePartial(partial)
        }
    }
}
