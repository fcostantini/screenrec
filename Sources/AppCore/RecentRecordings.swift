import Foundation
import RecorderCore

/// The menu's recent-file rows: the most-recent files in the output directory, newest first. Serves
/// both the recordings list (docs/06 "Menu — idle state" item 10, `.mov`) and the Recent Exports
/// group (M12-T2, `.mp4`/`.gif`) — same scan, different extension filter.
public enum RecentRecordings {

    /// docs/06: "up to 5 most-recent files".
    public static let limit = 5

    /// The Recent Exports group is smaller so derived files don't crowd the menu (M12-T2).
    public static let exportLimit = 3

    /// The share-format exports (M12-T2, M10): the sibling files `Export as MP4` / `Save as GIF` write.
    /// Aliases the writers' own list, so this and the orphan sweep can't drift apart (M15-T3).
    public static let exportExtensions = OutputLocation.exportExtensions

    /// A directory entry, reduced to the two things the choosing depends on.
    struct Entry: Equatable {
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
        return "\(name) — \(clock(duration)) · \(size)"
    }

    /// `M:SS` through `KeyframeIndex.timecode`, growing to `H:MM:SS` past an hour — the menu's
    /// tighter form of docs/06's `HH:MM:SS`. Rounds first, since a row is a label, not a cut point.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        guard whole >= 3600 else { return KeyframeIndex.timecode(Double(whole)) }
        return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }

    /// Picks the newest entries. Pure, split from the environment-dependent directory read so
    /// the choosing is testable on its own.
    ///
    /// Ties break on filename descending, for determinism only: `sorted(by:)` isn't guaranteed
    /// stable, so same-second files could otherwise swap places between menu openings. This is
    /// not a recency order — "Recording.mov" sorts above the later-written "Recording 2.mov".
    static func newest(_ entries: [Entry], limit: Int = limit) -> [URL] {
        entries
            .sorted { ($0.modified, $0.url.lastPathComponent) > ($1.modified, $1.url.lastPathComponent) }
            .prefix(limit)
            .map(\.url)
    }

    /// Live probe of `directory`, keeping only files whose extension is in `extensions` (lowercased).
    ///
    /// Non-throwing: a missing or unreadable output directory (unmounted volume) means no rows,
    /// not an error — the menu still has to open. The failure surfaces at record time instead,
    /// where it can be acted on.
    public static func inDirectory(
        _ directory: URL, extensions: Set<String> = ["mov"], limit: Int = limit
    ) -> [URL] {
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

    /// Size and duration for each of `urls`, reusing `cached` for any file whose size and
    /// modification date are unchanged — so a repeat menu open reads nothing, and only a genuinely
    /// new file pays for an asset load. Files that can't be read are dropped, which is what evicts
    /// trashed ones.
    static func details(for urls: [URL], cached: [URL: RowDetail]) async -> [URL: RowDetail] {
        var fresh: [URL: RowDetail] = [:]
        for url in urls {
            // `URL` caches resource values per instance, and the menu holds the same URLs across
            // opens — without this, a re-recorded file keeps its first size and length forever.
            var probe = url
            probe.removeAllCachedResourceValues()
            guard let values = try? probe.resourceValues(
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
