import Foundation

/// Which derive actions apply to a file (M24-T5), decided by container in one place — so the menu
/// can't offer what the exporters would refuse, and a new surface can't disagree with the old one.
///
/// Two rules. **A GIF isn't a movie:** `AVURLAsset` reports `isReadable false`, no video tracks and
/// a duration of `-1` for one, so every derive on a GIF row ends in a failure notice (docs/07) —
/// and an `AVAssetExportSession` is still created for it, which is why it never failed at the menu.
/// **A derive must make something you don't already have:** offering `Export as MP4` on an `.mp4`
/// re-encodes what's in front of you.
///
/// The audio export (M38-T2) makes the second rule bite on a whole class of file rather than one
/// extension: an `.m4a` this app wrote is a row in the same menu, and three of these derives need a
/// picture it hasn't got while the fourth would hand back what you already have.
public struct DeriveOptions: Equatable, Sendable {
    public let canExportToMP4: Bool
    public let canSaveAsGIF: Bool
    public let canTrim: Bool
    public let canExportAudio: Bool

    /// Sound, with no picture to derive anything from — including what this app's own audio export
    /// writes.
    private static let audioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "flac",
    ]

    public init(for url: URL) {
        let ext = url.pathExtension.lowercased()
        // Unknown extensions are treated as movies: the exporters fail loudly and honestly, which
        // beats hiding an action that would have worked.
        let isMovie = ext != "gif" && !Self.audioExtensions.contains(ext)
        canExportToMP4 = isMovie && ext != "mp4" && ext != "m4v"
        canSaveAsGIF = isMovie
        canTrim = isMovie
        canExportAudio = isMovie
    }

    /// Whether any derive applies — the menu's divider hangs off this, so a file with none of them
    /// doesn't leave two rules stacked together.
    public var hasAny: Bool { canExportToMP4 || canSaveAsGIF || canTrim || canExportAudio }
}
