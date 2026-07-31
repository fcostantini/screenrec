import Foundation
import Observation
import RecorderCore
import os

/// The export/trim cluster, split out of `AppState` (M14-T1) — the `PermissionsModel` pattern. It
/// runs a share export or lossless trim off the main path, tracks the one-at-a-time in-flight state,
/// and holds the receipt (persisted, M12-T2/T3). Two inputs: `defaults` (receipt persistence) and a
/// `notify` closure (the outcome notification), both supplied by AppState. It never touches
/// `session`/`replay`/capture-config — a genuinely separable unit.
@MainActor
@Observable
public final class ExportModel {

    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "export")

    /// Posts the export outcome (M10-T2). Wired by AppState from its notifier; nil in tests.
    public var notify: (@MainActor (RecordingNotification) -> Void)?

    /// The source filename of the export in flight (M10-T2, MP4 or GIF), or nil when idle: the menu
    /// shows an "Exporting…" row and blocks a second export. One at a time, either format.
    public private(set) var exportInProgress: String?

    /// The most recent export, for the menu receipt (reveals the file). Replaced by the next, and
    /// persisted so it survives relaunch (M12-T2) — the didSet mirrors every change to the store;
    /// a rename re-points it, a trash clears it. Seeded in `init` (validated), where the didSet
    /// deliberately does not fire.
    public private(set) var lastExport: LastExport? {
        didSet {
            guard lastExport != oldValue else { return }
            SettingsStore.saveLastExport(lastExport, to: defaults)
        }
    }

    /// The transcode and the GIF encode, injected so tests exercise the wiring without the hardware
    /// codecs. Each returns where it wrote. Default to the production `Exporter`/`GifExporter`/`Trimmer`.
    public var exportFunction: @Sendable (_ source: URL, _ output: URL, _ configuration: ExportConfiguration, _ range: ExportRange?, _ crop: CropRect?) async throws -> URL = {
        try await Exporter.exportToMP4(from: $0, to: $1, configuration: $2, range: $3, crop: $4).url
    }
    public var gifExportFunction: @Sendable (_ source: URL, _ output: URL, _ configuration: GifConfiguration) async throws -> URL = {
        try await GifExporter.exportGIF(from: $0, to: $1, configuration: $2).url
    }
    public var trimFunction: @Sendable (_ source: URL, _ output: URL, _ start: Double, _ end: Double, _ mode: TrimMode) async throws -> URL = {
        try await Trimmer.trim(from: $0, to: $1, start: $2, end: $3, mode: $4).url
    }

    /// Puts a finished file on the pasteboard (M21-T2). Injected by the app — `NSPasteboard` is
    /// AppKit, which AppCore may not import (docs/01).
    public var copyToPasteboard: (@MainActor (URL) -> Void)?

    /// Free space on the volume holding a path, for the fit check (M23-T2). Injected so tests need
    /// no real disk — `DiskSpaceMonitor`'s own reason for taking the same seam.
    var availableBytes: @Sendable (String) -> Int64? = {
        DiskSpaceMonitor.availableBytes(forVolumeAtPath: $0)
    }

    /// The recording the Trim window is editing (M10-T4), or nil. Set when `Trim…` opens the window;
    /// the view reads it. Transient — not persisted.
    public var trimTarget: URL?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        // The persisted export receipt (M12-T2), validated: dropped if the file is gone. Set here,
        // where property observers don't fire, so seeding doesn't re-save. Staleness (M12-T3) is
        // judged at menu open, not here.
        lastExport = SettingsStore.loadLastExport(from: defaults)
    }

    // MARK: - Actions

    /// Transcodes a recording or saved clip to a shareable `.mp4` (M10-T2), or just `range` of it
    /// (M21-T1). The size comes from Settings (M18-T2) — AppState builds the `configuration`, as it
    /// does for GIF.
    public func exportToMP4(
        _ source: URL, configuration: ExportConfiguration, range: ExportRange? = nil
    ) {
        let export = exportFunction  // snapshot; the closure captures no `self`
        performExport(
            source, to: Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: source, range: range)),
            estimate: { await Self.mp4Bytes(of: source, configuration: configuration, range: range) },
            using: { try await export($0, $1, configuration, range, nil) },
            success: { RecordingNotifications.exported(url: $0) },
            failure: RecordingNotifications.exportFailed)
    }

    /// Exports `source` — or just `range` of it (M24-T1), or just `crop` of each frame (M26-T2) —
    /// and leaves the result on the pasteboard (M21-T2): the same off-main, one-at-a-time path,
    /// ending in one notice rather than an export receipt plus a copy.
    public func exportAndCopy(
        _ source: URL, configuration: ExportConfiguration, range: ExportRange? = nil,
        crop: CropRect? = nil
    ) {
        let export = exportFunction  // snapshot; the closure captures no `self`
        let copy = copyToPasteboard
        // With no pasteboard injected (tests, or an unwired app) the export still runs, but the
        // notice must not claim a copy that never happened.
        let notice = copy == nil
            ? RecordingNotifications.exported(url:)
            : RecordingNotifications.copiedToPasteboard(url:)
        performExport(
            source, to: Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: source, range: range)),
            estimate: {
                await Self.mp4Bytes(
                    of: source, configuration: configuration, range: range, crop: crop)
            },
            using: { try await export($0, $1, configuration, range, crop) },
            success: notice,
            failure: RecordingNotifications.exportFailed,
            completion: copy)
    }

    /// Saves a recording or clip as a looping GIF (M10-T3), the same off-main, one-at-a-time path.
    /// The caps come from Settings — AppState builds the `configuration` and passes it in.
    ///
    /// Deliberately unguarded by `ExportRoom` (M23-T2): LZW output size is content-dependent and
    /// lands either side of the source, so any estimate would refuse GIFs that fit and pass ones
    /// that don't. GIFs are also the smallest thing here, capped by their own fps/width.
    public func exportToGIF(_ source: URL, configuration: GifConfiguration) {
        let gifExport = gifExportFunction  // snapshot the value; the closure captures no `self`
        performExport(
            source, to: Exporter.availableURL(basedOn: GifExporter.gifSibling(of: source)),
            using: { try await gifExport($0, $1, configuration) },
            success: { RecordingNotifications.savedAsGIF(url: $0) },
            failure: RecordingNotifications.gifExportFailed)
    }

    /// Trims `source` to `[start, end]` (M10-T4; `mode` M18-T1), the same off-main, one-at-a-time
    /// path.
    public func trim(_ source: URL, from start: Double, to end: Double, mode: TrimMode) {
        let trim = trimFunction  // snapshot; the closure captures no `self`
        performExport(
            source, to: Exporter.availableURL(basedOn: Trimmer.trimmedSibling(of: source)),
            // A trim keeps a subset of the source's samples, so the whole source is a ceiling for
            // it — no rate model needed, and it can only over-quote.
            estimate: { Self.fileBytes(of: source) },
            using: { try await trim($0, $1, start, end, mode) },
            success: { RecordingNotifications.trimmed(url: $0) },
            failure: RecordingNotifications.trimFailed)
    }

    /// Runs an export off the main path — the menu row and the notification carry the outcome. One
    /// export at a time; the source is only read, so it never touches a live recording. Only a
    /// success sets `lastExport`; the "Exporting…" row shadows any prior receipt while this runs,
    /// so a failed re-export leaves the previous export's pointer intact.
    ///
    /// `estimate` predicts the output's size so the volume can be checked before anything is
    /// written (M23-T2). Nil means this kind of export has no defensible prediction, and runs
    /// unguarded — see `ExportRoom.fits`.
    private func performExport(
        _ source: URL,
        to output: URL,
        estimate: (@Sendable () async -> Int64?)? = nil,
        using export: @escaping @Sendable (URL, URL) async throws -> URL,
        success: @escaping (URL) -> RecordingNotification,
        failure: @escaping () -> RecordingNotification,
        completion: (@MainActor (URL) -> Void)? = nil
    ) {
        guard exportInProgress == nil else { return }
        exportInProgress = source.lastPathComponent
        let availableBytes = self.availableBytes
        exportTask = Task { [weak self, export] in
            // Before a byte is written: an export knows its own length, so a job that cannot land
            // is refused rather than failed part-way (the recording path's floor is the other
            // shape, for the other reason).
            if let shortfall = await Self.shortfall(
                writing: output, estimate: estimate, availableBytes: availableBytes) {
                guard let self else { return }
                exportInProgress = nil
                notify?(RecordingNotifications.exportNoRoom(shortfall))
                return
            }
            do {
                let url = try await export(source, output)
                guard let self else { return }
                exportInProgress = nil
                lastExport = LastExport(url: url, date: Date())
                completion?(url)      // before the notice, so "Copied" is true when it is read
                notify?(success(url))
            } catch {
                guard let self else { return }
                exportInProgress = nil
                Self.log.error("export failed: \(error.localizedDescription, privacy: .public)")
                notify?(failure())
            }
        }
    }

    /// What the export would need against what the volume has, or nil when it fits (or can't be
    /// judged). Off the main actor: both the header read and the volume probe are I/O.
    nonisolated private static func shortfall(
        writing output: URL, estimate: (@Sendable () async -> Int64?)?,
        availableBytes: @Sendable (String) -> Int64?
    ) async -> ExportRoom.Shortfall? {
        guard let estimate, let need = await estimate() else { return nil }
        let folder = output.deletingLastPathComponent().path
        // The folder, not the not-yet-existing file: probing a path that doesn't exist reads nil
        // forever and silently disables the check (the M19-T1 trap).
        guard let free = availableBytes(folder),
              !ExportRoom.fits(needBytes: need, freeBytes: free)
        else { return nil }
        return ExportRoom.Shortfall(
            needBytes: need, freeBytes: free,
            volumeName: ExportRoom.volumeName(forPath: folder))
    }

    /// The most a share export of `source` can weigh. Nil when the file's header can't be read —
    /// no figure beats a wrong one (M16-T2). The arithmetic itself is
    /// `ExportConfiguration.projectedBytes`, shared with the menu row that quotes a weight.
    nonisolated private static func mp4Bytes(
        of source: URL, configuration: ExportConfiguration, range: ExportRange?,
        crop: CropRect? = nil
    ) async -> Int64? {
        guard let pixels = await MediaFile.dimensions(of: source) else { return nil }
        let seconds: Double
        if let range {
            seconds = max(0, range.end - range.start)
        } else if let full = await MediaFile.duration(of: source) {
            seconds = full
        } else {
            return nil
        }
        // A crop is what gets encoded, so it is what the guard must weigh: quoting the whole frame
        // would refuse a cropped export that fits.
        return configuration.projectedBytes(
            sourceWidth: crop?.width ?? pixels.width, sourceHeight: crop?.height ?? pixels.height,
            seconds: seconds)
    }

    /// The source's size on disk, or nil if it can't be read.
    nonisolated private static func fileBytes(of source: URL) -> Int64? {
        (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    /// The export in flight, held so quitting can wait for it instead of killing it with the
    /// process (M23-T2) — the shape `SessionModel.consumeTask` uses for a recording.
    private var exportTask: Task<Void, Never>?

    /// Waits for an in-flight export to settle. Returns at once when none is running.
    public func waitForExportToFinish() async {
        await exportTask?.value
    }

    /// Abandons an in-flight export — the user chose to quit through it (M23-T2).
    ///
    /// Clears `exportInProgress` **synchronously**, before the cancellation is observed, so the
    /// quit that follows sees no work in flight. Without that, `applicationShouldTerminate` would
    /// turn "Quit Anyway" back into a wait, and the button would be a lie. Nothing is corrupted:
    /// the export writes to a `.partial` and only renames on success (M15-T3).
    public func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportInProgress = nil
    }

    // MARK: - The receipt

    /// The window an export receipt stays "fresh" (M12-T3): long enough that an export-then-relaunch
    /// keeps its receipt, short enough that one from an earlier day doesn't resurface.
    static let receiptFreshness: TimeInterval = 3600   // 1 hour

    /// Drops a persisted export receipt (M12-T2) that has aged past `receiptFreshness` (M12-T3) or
    /// whose file has gone. Called at menu open, riding the same stamp-at-open refresh as the
    /// recents (M6-T10). Existence is checked here, not only at launch: a file deleted mid-session
    /// would otherwise leave a row whose every action silently does nothing (M18-T4).
    public func expireStaleReceipt() {
        guard let export = lastExport else { return }
        if export.isStale(now: Date(), freshFor: Self.receiptFreshness)
            || !FileManager.default.fileExists(atPath: export.url.path) {
            lastExport = nil
        }
    }


    /// Re-points the receipt after a rename (M12-T2) if it named `oldURL`, keeping the export time —
    /// so a renamed old receipt doesn't become fresh. AppState's rename forwards here.
    public func renameReceipt(from oldURL: URL, to newURL: URL) {
        if let export = lastExport, export.url.isSameFile(as: oldURL) {
            lastExport = LastExport(url: newURL, date: export.date)
        }
    }

    /// Clears the receipt after a trash (M12-T2) if it named `url`. AppState's trash forwards here.
    public func clearReceipt(for url: URL) {
        if lastExport?.url.isSameFile(as: url) == true { lastExport = nil }
    }
}
