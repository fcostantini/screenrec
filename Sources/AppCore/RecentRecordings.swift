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
}
