import Foundation
import RecorderCore

/// The menu's recent-file rows: the most-recent files in the output directory, newest first. Serves
/// both the recordings list (docs/06 "Menu — idle state" item 10, `.mov`) and the Recent Exports
/// group (M12-T2, `.mp4`/`.gif`) — same scan, different extension filter.
public enum RecentRecordings {

    /// docs/06 item 10. Ten since M28-T5: five was a cap on how many near-identical timestamps a
    /// reader could tell apart, and thumbnails plus day headers removed that limit, not a taste for
    /// five.
    public static let limit = 10

    /// The Recent Exports group stays smaller so derived files don't crowd the menu (M12-T2).
    public static let exportLimit = 5

    /// The share-format exports (M12-T2, M10): the sibling files `Export as MP4` / `Save as GIF` write.
    /// Aliases the writers' own list, so this and the orphan sweep can't drift apart (M15-T3).
    public static let exportExtensions = OutputLocation.exportExtensions

    /// A directory entry, reduced to the two things the choosing depends on.
    struct Entry: Equatable, Sendable {
        let url: URL
        let modified: Date
    }

    /// What a row says about a file beyond its name (M18-T3), so picking the right take is one
    /// step. `duration` is nil when the file isn't readable media. `modified` is what the read was
    /// valid at, so the same value serves as the cache key.
    struct RowDetail: Equatable, Sendable {
        let byteCount: Int
        let duration: Double?
        let modified: Date
    }

    /// `Recording 2026-07-27 at 13.01.24.mov — 23:04 · 5.5 GB` (docs/06: names exactly as on disk,
    /// sizes through `ByteCountFormatter`). Name-only until the read lands, and name + size for a
    /// file that isn't readable media — a row states what is known, never a placeholder.
    static func rowTitle(for url: URL, detail: RowDetail?) -> String {
        let name = url.lastPathComponent
        guard let detail else { return name }
        let size = ByteCountFormatter.string(fromByteCount: Int64(detail.byteCount), countStyle: .file)
        guard let duration = detail.duration else { return "\(name) — \(size)" }
        return "\(name) — \(Timecode.length(duration)) · \(size)"
    }

    /// Picks the newest entries. Pure, split from the environment-dependent directory read so
    /// the choosing is testable on its own.
    ///
    /// Ties break on filename descending, for determinism only: `sorted(by:)` isn't guaranteed
    /// stable, so same-second files could otherwise swap places between menu openings. This is
    /// not a recency order — "Recording.mov" sorts above the later-written "Recording 2.mov".
    static func newest(_ entries: [Entry], limit: Int = limit) -> [Entry] {
        Array(entries
            .sorted { ($0.modified, $0.url.lastPathComponent) > ($1.modified, $1.url.lastPathComponent) }
            .prefix(limit))
    }

    /// Live probe of `directory`, keeping only files whose extension is in `extensions` (lowercased).
    ///
    /// Non-throwing: a missing or unreadable output directory (unmounted volume) means no rows,
    /// not an error — the menu still has to open. The failure surfaces at record time instead,
    /// where it can be acted on.
    public static func inDirectory(
        _ directory: URL, extensions: Set<String> = ["mov"], limit: Int = limit
    ) -> [URL] {
        entriesInDirectory(directory, extensions: extensions, limit: limit).map(\.url)
    }

    /// The same scan, keeping the modification dates it already reads — the day headers (M28-T5)
    /// need them, and re-reading them per row would be a second pass over the same files.
    static func entriesInDirectory(
        _ directory: URL, extensions: Set<String> = ["mov"], limit: Int = limit
    ) -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        let entries = contents.compactMap { url -> Entry? in
            guard extensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { return nil }
            return Entry(url: url, modified: modified)
        }
        return newest(entries, limit: limit)
    }

    /// The rows under the day they were made (M28-T5), in the order given. Pure: the caller
    /// supplies the dates, so grouping and its copy are testable without a disk.
    ///
    /// A file whose date is unknown joins the group above it rather than inventing one, and an
    /// empty label means the group takes no header at all.
    public static func grouped(
        _ urls: [URL], dates: [URL: Date], now: Date,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> [(label: String, urls: [URL])] {
        var groups: [(label: String, urls: [URL])] = []
        for url in urls {
            let label = dates[url].map {
                dayLabel(for: $0, now: now, calendar: calendar, locale: locale)
            }
            // No date and nothing above it: a header would be a guess, so the rows go bare.
            let resolved = label ?? groups.last?.label ?? ""
            if groups.last?.label == resolved {
                groups[groups.count - 1].urls.append(url)
            } else {
                groups.append((label: resolved, urls: [url]))
            }
        }
        return groups
    }

    /// `Today` · `Yesterday` · a weekday inside the last week · `17 July` beyond it. The weekday
    /// only reads unambiguously within seven days, which is what bounds it.
    public static func dayLabel(
        for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        formatter.setLocalizedDateFormatFromTemplate((1...6).contains(days) ? "EEEE" : "dMMMM")
        return formatter.string(from: date)
    }

    /// Size and duration for each of `urls`, reusing `cached` for any file whose size and
    /// modification date are unchanged — so a repeat menu open reads nothing, and only a genuinely
    /// new file pays for an asset load. Files that can't be read are dropped, which is what evicts
    /// trashed ones.
    static func details(for urls: [URL], cached: [URL: RowDetail]) async -> [URL: RowDetail] {
        var fresh: [URL: RowDetail] = [:]
        for url in urls {
            guard let values = url.freshResourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let bytes = values.fileSize, let modified = values.contentModificationDate
            else { continue }
            if let hit = cached[url], hit.modified == modified, hit.byteCount == bytes {
                fresh[url] = hit
                continue
            }
            fresh[url] = RowDetail(
                byteCount: bytes, duration: await MediaFile.duration(of: url), modified: modified)
        }
        return fresh
    }
}
