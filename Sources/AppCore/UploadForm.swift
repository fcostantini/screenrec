import Foundation
import UploadCore

/// The upload sheet's rules (M40-T3). YouTube's limits are applied as the user types, so a title
/// it would refuse can't be sent — a refusal after the export and the transfer costs minutes.
/// Its API terms say a client must not set a *shorter* limit than these.
public enum UploadForm {
    public static let titleLimit = 100
    public static let descriptionByteLimit = 5000
    /// Past this, YouTube takes the video only from a channel that has verified a phone number.
    public static let longVideoSeconds: Double = 15 * 60

    /// `text` as YouTube would accept it for a title: no angle brackets, at most 100 characters.
    public static func title(_ text: String) -> String {
        String(withoutAngleBrackets(text).prefix(titleLimit))
    }

    /// The limit is in bytes, so the cut falls on a character boundary at or under it — never
    /// through the middle of one.
    public static func description(_ text: String) -> String {
        var kept = ""
        var bytes = 0
        for character in withoutAngleBrackets(text) {
            bytes += String(character).utf8.count
            guard bytes <= descriptionByteLimit else { break }
            kept.append(character)
        }
        return kept
    }

    /// Where the insertion point belongs once `rule` has rewritten `text`: after what is left of
    /// the text that was before it. Offsets are UTF-16, as AppKit's selection is.
    public static func caret(_ caret: Int, in text: String, after rule: (String) -> String) -> Int {
        let whole = text as NSString
        let before = whole.substring(to: min(max(caret, 0), whole.length))
        return min((rule(before) as NSString).length, (rule(text) as NSString).length)
    }

    public static func canUpload(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the sheet's title starts as: the recording's own name.
    public static func defaultTitle(for source: URL) -> String {
        title(source.deletingPathExtension().lastPathComponent)
    }

    /// The same for a clip already exported: its name without the ending the export added to
    /// tell it from its source — ` trimmed`, or ` trimmed 2`…`99` once a copy existed. Nothing
    /// looser: a take that merely has the word in its name keeps it, and no name is cut to nothing.
    public static func defaultTitle(forExport file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        let stem = name.replacing(#/ trimmed( [0-9]{1,2})?$/#, with: "")
        return title(stem.isEmpty ? name : stem)
    }

    public static func isLong(seconds: Double) -> Bool {
        seconds > longVideoSeconds
    }

    /// What is sent, whatever reached the fields and however: the rules applied once more, and a
    /// title left blank replaced by `fallbackTitle`, since YouTube refuses an empty one.
    public static func metadata(
        title: String, description: String, privacy: VideoMetadata.Privacy, fallbackTitle: String
    ) -> VideoMetadata {
        let trimmed = self.title(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return VideoMetadata(
            title: trimmed.isEmpty ? fallbackTitle : trimmed,
            description: self.description(description)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            privacy: privacy)
    }

    private static func withoutAngleBrackets(_ text: String) -> String {
        text.filter { $0 != "<" && $0 != ">" }
    }
}

/// Everything the upload sheet shows before the user has typed anything.
public struct UploadDraft: Equatable, Sendable {
    public var title: String
    public var privacy: VideoMetadata.Privacy
    /// `0:24 · up to 18 MB · H.264 1920 × 1200`, or shorter while the source's geometry loads.
    public var summary: String
    public var channel: String?
    public var isLong: Bool

    public init(
        title: String, privacy: VideoMetadata.Privacy, summary: String, channel: String?,
        isLong: Bool
    ) {
        self.title = title
        self.privacy = privacy
        self.summary = summary
        self.channel = channel
        self.isLong = isLong
    }
}
