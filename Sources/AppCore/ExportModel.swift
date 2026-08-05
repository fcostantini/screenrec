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

    /// The source filename of the export **running now** (M10-T2, MP4 or GIF), or nil when nothing
    /// is. The menu shows an "Exporting…" row for it; anything requested meanwhile joins
    /// `pending` rather than being refused (M33-T1). One at a time, either format.
    public private(set) var exportInProgress: String?

    /// How far the export in flight has got, 0…1 — or nil for one whose progress cannot be known
    /// (GIF and trim report none), where the row says only that it is running (M28-T4).
    public private(set) var exportProgress: Double?

    /// Distinguishes one export from the next, so a straggling report from a cancelled transcode
    /// cannot land on its successor.
    private var exportGeneration = 0

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
    public var exportFunction: @Sendable (_ source: URL, _ output: URL, _ configuration: ExportConfiguration, _ range: ExportRange?, _ crop: CropRect?, _ progress: @escaping @Sendable (Double) -> Void) async throws -> URL = {
        try await Exporter.exportToMP4(
            from: $0, to: $1, configuration: $2, range: $3, crop: $4, progress: $5).url
    }
    public var gifExportFunction: @Sendable (_ source: URL, _ output: URL, _ configuration: GifConfiguration) async throws -> URL = {
        try await GifExporter.exportGIF(from: $0, to: $1, configuration: $2).url
    }
    public var trimFunction: @Sendable (_ source: URL, _ output: URL, _ start: Double, _ end: Double, _ mode: TrimMode, _ crop: CropRect?) async throws -> URL = {
        try await Trimmer.trim(from: $0, to: $1, start: $2, end: $3, mode: $4, crop: $5).url
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
            using: { try await export($0, $1, configuration, range, nil, $2) },
            success: { RecordingNotifications.exported(url: $0) },
            failure: RecordingNotifications.exportFailed,
            reportsProgress: true)
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
            using: { try await export($0, $1, configuration, range, crop, $2) },
            success: notice,
            failure: RecordingNotifications.exportFailed,
            reportsProgress: true,
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
            using: { source, output, _ in try await gifExport(source, output, configuration) },
            success: { RecordingNotifications.savedAsGIF(url: $0) },
            failure: RecordingNotifications.gifExportFailed)
    }

    /// Trims `source` to `[start, end]` (M10-T4; `mode` M18-T1), keeping only `crop` of each frame
    /// when there is one (M26-T4, precise mode only), on the same off-main, one-at-a-time path.
    public func trim(
        _ source: URL, from start: Double, to end: Double, mode: TrimMode, crop: CropRect? = nil
    ) {
        let trim = trimFunction  // snapshot; the closure captures no `self`
        performExport(
            source, to: Exporter.availableURL(basedOn: Trimmer.trimmedSibling(of: source)),
            // A trim keeps a subset of the source's samples, so the whole source is a ceiling for
            // it — no rate model needed, and it can only over-quote.
            estimate: { Self.fileBytes(of: source) },
            using: { source, output, _ in try await trim(source, output, start, end, mode, crop) },
            success: { RecordingNotifications.trimmed(url: $0) },
            failure: RecordingNotifications.trimFailed)
    }

    /// One queued export: everything `run` needs when its turn comes (M33-T1).
    private struct PendingExport {
        let source: URL
        let output: URL
        let estimate: (@Sendable () async -> Int64?)?
        let export: @Sendable (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> URL
        let success: (URL) -> RecordingNotification
        let failure: () -> RecordingNotification
        let reportsProgress: Bool
        let completion: (@MainActor (URL) -> Void)?
    }

    /// Jobs waiting behind the one running. Still one at a time — that just no longer means "one at
    /// a time or nothing". Not persisted: a queued job is an intention with nothing on disk, and the
    /// `.partial` discipline is not a job store, so quitting says what it drops (`cancelExport`).
    private var pending: [PendingExport] = []

    /// How many exports are waiting behind the running one, for the menu's single row.
    public var queuedExportCount: Int { pending.count }

    /// Queues an export and starts it when its turn comes (M33-T1) — the menu row and the
    /// notification carry the outcome. Still **one at a time**, so the encoders are never
    /// oversubscribed; the source is only read, so it never touches a live recording. Only a success
    /// sets `lastExport`; the "Exporting…" row shadows any prior receipt while this runs, so a
    /// failed re-export leaves the previous export's pointer intact.
    ///
    /// `estimate` predicts the output's size so the volume can be checked before anything is
    /// written (M23-T2), and it runs at the job's **turn** rather than at enqueue. Nil means this
    /// kind of export has no defensible prediction, and runs unguarded — see `ExportRoom.fits`.
    private func performExport(
        _ source: URL,
        to output: URL,
        estimate: (@Sendable () async -> Int64?)? = nil,
        using export: @escaping @Sendable (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> URL,
        success: @escaping (URL) -> RecordingNotification,
        failure: @escaping () -> RecordingNotification,
        reportsProgress: Bool = false,
        completion: (@MainActor (URL) -> Void)? = nil
    ) {
        pending.append(
            PendingExport(
                source: source, output: output, estimate: estimate, export: export,
                success: success, failure: failure, reportsProgress: reportsProgress,
                completion: completion))
        startNextIfIdle()
    }

    /// Takes the next job when nothing is running. The single-runner invariant lives here, so no
    /// caller has to hold it.
    private func startNextIfIdle() {
        guard exportInProgress == nil, !pending.isEmpty else { return }
        run(pending.removeFirst())
    }

    private func run(_ job: PendingExport) {
        exportGeneration += 1
        exportInProgress = job.source.lastPathComponent
        exportProgress = job.reportsProgress ? 0 : nil
        let availableBytes = self.availableBytes
        // Built here, after the generation moves, so the sink belongs to this run and no other.
        let report = progressReporter()
        exportTask = Task { [weak self, job] in
            // At this job's turn, never at enqueue: a queue judged up front would weigh every job
            // against space the ones ahead of it have not spent yet.
            //
            // Before a byte is written: an export knows its own length, so a job that cannot land
            // is refused rather than failed part-way (the recording path's floor is the other
            // shape, for the other reason).
            let shortfall = await Self.shortfall(
                writing: job.output, estimate: job.estimate, availableBytes: availableBytes)
            // Unwrapped once, so the `finish()` that releases the queue is reachable from every
            // ending below rather than only from the ones inside a binding.
            guard let self else { return }
            if let shortfall {
                notify?(RecordingNotifications.exportNoRoom(shortfall))
                return finish()
            }
            do {
                let url = try await job.export(job.source, job.output, report)
                lastExport = LastExport(url: url, date: Date())
                job.completion?(url)  // before the notice, so "Copied" is true when it is read
                notify?(job.success(url))
            } catch {
                Self.log.error("export failed: \(error.localizedDescription, privacy: .public)")
                notify?(job.failure())
            }
            finish()
        }
    }

    /// Clears the running state and takes the next job. Every ending routes through here, so one
    /// that fails or is refused cannot strand the queue behind it.
    private func finish() {
        exportInProgress = nil
        exportProgress = nil
        startNextIfIdle()
    }

    /// The sink handed to the exporter, which reports from a background queue — every update lands
    /// on the main actor, where the menu reads it.
    private func progressReporter() -> @Sendable (Double) -> Void {
        let generation = exportGeneration
        return { [weak self] fraction in
            Task { @MainActor in
                // A cancelled export's transcode keeps running and keeps reporting; without the
                // generation it could resurrect a stale bar, or overwrite the next export's.
                guard let self, generation == self.exportGeneration else { return }
                self.exportProgress = fraction
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

    /// Waits for the whole queue to settle, not just the job running now. Returns at once when
    /// nothing is in flight. Each ending starts its successor on the main actor before its task
    /// resolves, so by the time one `await` returns `exportTask` is already the next one.
    public func waitForExportToFinish() async {
        while exportInProgress != nil || !pending.isEmpty {
            guard let task = exportTask else { return }
            await task.value
        }
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
        // The queue goes too: quitting means quitting, and the confirmation says how many that is
        // (M33-T1). Clearing it before the runner stops is what keeps `startNextIfIdle` from
        // reviving one on the way out.
        pending.removeAll()
        exportInProgress = nil
        exportProgress = nil
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
