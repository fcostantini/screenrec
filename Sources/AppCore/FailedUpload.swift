import Foundation
import UploadCore

/// The upload that failed last, for the menu's row (M40-T6): what it was, why it stopped, and
/// whether it can be tried again. Kept in memory only — not across a quit (M40's scope).
public struct FailedUpload: Equatable, Sendable {
    /// Which failure this is. Its clip can be renamed while a press on its row is still under
    /// way, and the row must go on meaning the same upload.
    public let id = UUID()
    public let title: String
    /// The clip. It can have been moved or trashed since.
    public var file: URL
    public let failure: UploadFailure
    public let date: Date
    /// YouTube holds an unfinished entry for it, which this app cannot delete (07).
    public let leavesEntry: Bool

    public var canTryAgain: Bool { failure.canRetry }

    public var menuTitle: String { "Couldn't upload · \(UploadCopy.shortened(title))" }

    /// A failure is unfinished business rather than news, so it stays longer than a receipt's
    /// hour — but not for the days this app runs.
    static let lifetime: TimeInterval = 24 * 3600

    func isStale(now: Date) -> Bool { now.timeIntervalSince(date) > Self.lifetime }
}
