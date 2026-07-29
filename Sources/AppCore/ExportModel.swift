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
    public var exportFunction: @Sendable (_ source: URL, _ output: URL, _ configuration: ExportConfiguration, _ range: ExportRange?) async throws -> URL = {
        try await Exporter.exportToMP4(from: $0, to: $1, configuration: $2, range: $3).url
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
            using: { try await export($0, $1, configuration, range) },
            success: { RecordingNotifications.exported(url: $0) },
            failure: RecordingNotifications.exportFailed)
    }

    /// Exports `source` and leaves the result on the pasteboard (M21-T2) — the same off-main,
    /// one-at-a-time path, ending in one notice rather than an export receipt plus a copy.
    public func exportAndCopy(_ source: URL, configuration: ExportConfiguration) {
        let export = exportFunction  // snapshot; the closure captures no `self`
        let copy = copyToPasteboard
        // With no pasteboard injected (tests, or an unwired app) the export still runs, but the
        // notice must not claim a copy that never happened.
        let notice = copy == nil
            ? RecordingNotifications.exported(url:)
            : RecordingNotifications.copiedToPasteboard(url:)
        performExport(
            source, to: Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: source)),
            using: { try await export($0, $1, configuration, nil) },
            success: notice,
            failure: RecordingNotifications.exportFailed,
            completion: copy)
    }

    /// Saves a recording or clip as a looping GIF (M10-T3), the same off-main, one-at-a-time path.
    /// The caps come from Settings — AppState builds the `configuration` and passes it in.
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
            using: { try await trim($0, $1, start, end, mode) },
            success: { RecordingNotifications.trimmed(url: $0) },
            failure: RecordingNotifications.trimFailed)
    }

    /// Runs an export off the main path — the menu row and the notification carry the outcome. One
    /// export at a time; the source is only read, so it never touches a live recording. Only a
    /// success sets `lastExport`; the "Exporting…" row shadows any prior receipt while this runs,
    /// so a failed re-export leaves the previous export's pointer intact.
    private func performExport(
        _ source: URL,
        to output: URL,
        using export: @escaping @Sendable (URL, URL) async throws -> URL,
        success: @escaping (URL) -> RecordingNotification,
        failure: @escaping () -> RecordingNotification,
        completion: (@MainActor (URL) -> Void)? = nil
    ) {
        guard exportInProgress == nil else { return }
        exportInProgress = source.lastPathComponent
        Task { [weak self, export] in
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
