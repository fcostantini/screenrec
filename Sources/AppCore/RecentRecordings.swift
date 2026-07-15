import Foundation

/// The menu's recent-recordings rows (docs/06 "Menu — idle state", item 10): the most-recent
/// files in the output directory, newest first, clicking one reveals it in Finder.
public enum RecentRecordings {

    /// docs/06: "up to 5 most-recent files".
    public static let limit = 5

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

    /// Live probe of `directory`.
    ///
    /// Non-throwing: a missing or unreadable output directory (unmounted volume) means no rows,
    /// not an error — the menu still has to open. The failure surfaces at record time instead,
    /// where it can be acted on.
    public static func inDirectory(_ directory: URL, limit: Int = limit) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        let entries = contents.compactMap { url -> Entry? in
            guard url.pathExtension.lowercased() == "mov",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { return nil }
            return Entry(url: url, modified: modified)
        }
        return newest(entries, limit: limit)
    }
}
