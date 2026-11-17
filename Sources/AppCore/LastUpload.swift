import Foundation
import UploadCore

/// The most recent upload, for the menu's receipt (M40-T4) — `LastExport`'s counterpart, persisted
/// and aged the same way. Once the notice has gone this is the one place the link can be read.
public struct LastUpload: Equatable, Sendable {
    public let videoID: String
    public let title: String
    /// The clip that was sent. It can have been moved or trashed since; the link works regardless.
    public let file: URL
    public let date: Date

    public init(videoID: String, title: String, file: URL, date: Date) {
        self.videoID = videoID
        self.title = title
        self.file = file
        self.date = date
    }

    /// A menu is as wide as its widest row and cannot truncate one, and a title runs to 100
    /// characters — so the row carries the start of it.
    public var menuTitle: String {
        let shown = title.count > Self.titleLength
            ? title.prefix(Self.titleLength - 1) + "…" : Substring(title)
        return "Uploaded to YouTube · \(shown)"
    }

    private static let titleLength = 40

    public var link: String { UploadedVideo.link(forID: videoID) }
    public var watchURL: URL? { URL(string: link) }
    /// Where the title and visibility are changed and the video deleted: the upload-only
    /// permission lets this app do none of it.
    public var studioURL: URL? { URL(string: "https://studio.youtube.com/video/\(videoID)/edit") }

    public func isStale(now: Date, freshFor: TimeInterval) -> Bool {
        now.timeIntervalSince(date) > freshFor
    }
}
