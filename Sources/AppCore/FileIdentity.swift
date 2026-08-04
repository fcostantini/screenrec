import Foundation

extension URL {
    /// Whether two file URLs name the same file, robust to representation differences — a receipt
    /// loaded from a stored path vs a `contentsOfDirectory`-derived row URL (M12-T2).
    ///
    /// Deliberately a path comparison, not `Exporter.sameFile`'s resource-identifier check: this
    /// answers "does this receipt point at that row", which must still work once the file is gone.
    func isSameFile(as other: URL) -> Bool {
        standardizedFileURL == other.standardizedFileURL
    }

    /// Resource values read past `URL`'s per-instance cache. The menu holds the same URLs across
    /// opens, so without this a re-recorded file keeps its first size, length and frame forever
    /// (M18-T3).
    func freshResourceValues(forKeys keys: Set<URLResourceKey>) -> URLResourceValues? {
        var probe = self
        probe.removeAllCachedResourceValues()
        return try? probe.resourceValues(forKeys: keys)
    }
}
