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

    /// Picks the newest entries. Split from the directory read on purpose: reading a directory
    /// is environment-dependent and this is not, and the M3-T3 disk guard is the standing lesson
    /// about what happens when the two are welded together — a test of the volume-dependent half
    /// passed for weeks while the behaviour it claimed to cover was wrong everywhere but the boot
    /// volume. So the decision is pure, and the probe below is a thin shell over it.
    ///
    /// Ties break on filename, descending — for determinism only. `sorted(by:)` is not
    /// guaranteed stable, so without a tie-break two same-second files could swap places between
    /// menu openings for no reason the user could see.
    ///
    /// It does *not* order same-second files by recency, and shouldn't be read as doing so:
    /// "Recording.mov" sorts above "Recording 2.mov" even though the suffixed one was written
    /// second (the O_EXCL collision path, M2-T4). Which of two files written in the same second
    /// is listed first is cosmetic; that the list stops moving on its own is not.
    static func newest(_ entries: [Entry], limit: Int = limit) -> [URL] {
        entries
            .sorted { ($0.modified, $0.url.lastPathComponent) > ($1.modified, $1.url.lastPathComponent) }
            .prefix(limit)
            .map(\.url)
    }

    /// Live probe of `directory`.
    ///
    /// Deliberately non-throwing: a missing or unreadable output directory means no rows, not an
    /// error dialog. The user may have pointed the app at a folder that has since gone (an
    /// unmounted volume), and the menu still has to open — the failure surfaces when they try to
    /// record, where it can be acted on, not when they glance at the menu bar.
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
