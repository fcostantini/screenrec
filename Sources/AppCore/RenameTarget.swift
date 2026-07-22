import Foundation

/// Computes the destination of a Rename… (M12-T2), keeping the file in place and its extension
/// intact — a rename is a new name, not a move. Pure, so the naming rules are unit-tested; the
/// caller resolves collisions (`Exporter.availableURL`) and performs the move.
public enum RenameTarget {

    /// The URL `url` should become when renamed to `newBaseName` (extension unchanged), or nil for
    /// a no-op: a blank name, the name it already has, or a name containing a path separator.
    public static func compute(for url: URL, newBaseName: String) -> URL? {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              trimmed != url.deletingPathExtension().lastPathComponent
        else { return nil }

        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let renamed = directory.appendingPathComponent(trimmed)
        return ext.isEmpty ? renamed : renamed.appendingPathExtension(ext)
    }
}
