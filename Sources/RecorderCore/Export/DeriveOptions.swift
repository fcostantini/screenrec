import Foundation

/// Which derive actions apply to a file (M24-T5), decided by container in one place — so the menu
/// can't offer what the exporters would refuse, and a new surface can't disagree with the old one.
///
/// Two rules. **A GIF isn't a movie:** `AVURLAsset` reports `isReadable false`, no video tracks and
/// a duration of `-1` for one, so every derive on a GIF row ends in a failure notice (docs/07) —
/// and an `AVAssetExportSession` is still created for it, which is why it never failed at the menu.
/// **A derive must make something you don't already have:** offering `Export as MP4` on an `.mp4`
/// re-encodes what's in front of you.
public struct DeriveOptions: Equatable, Sendable {
    public let canExportToMP4: Bool
    public let canSaveAsGIF: Bool
    public let canTrim: Bool

    public init(for url: URL) {
        let ext = url.pathExtension.lowercased()
        // Unknown extensions are treated as movies: the exporters fail loudly and honestly, which
        // beats hiding an action that would have worked.
        let isMovie = ext != "gif"
        canExportToMP4 = isMovie && ext != "mp4" && ext != "m4v"
        canSaveAsGIF = isMovie
        canTrim = isMovie
    }

    /// Whether any derive applies — the menu's divider hangs off this, so a file with none of them
    /// doesn't leave two rules stacked together.
    public var hasAny: Bool { canExportToMP4 || canSaveAsGIF || canTrim }
}
