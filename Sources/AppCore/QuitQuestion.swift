import Foundation

/// What to ask before a quit that would lose work (docs/06 item 12; uploads since M40-T4). Pure,
/// so every form is asserted without an alert on screen.
public struct QuitQuestion: Equatable, Sendable {
    public let title: String
    public let body: String
    /// The default button: wait for everything, then quit.
    public let wait: String

    public static let quitAnyway = "Quit Anyway"

    /// What stopping an upload YouTube has already opened leaves behind (07): said before the
    /// choice, because this app cannot clean it up afterwards.
    static let entrySentence =
        "YouTube keeps an unfinished entry for the upload already under way; you can delete it "
        + "in YouTube Studio."

    /// `exports` and `uploads` count everything outstanding of each kind — running, waiting and,
    /// for uploads, the ones an export has yet to start. `leavesEntry` is whether an upload has
    /// got as far as YouTube. Nil when a quit would lose nothing.
    public init?(exports: Int, uploads: Int, leavesEntry: Bool = false) {
        guard exports > 0 || uploads > 0 else { return nil }
        // Only the two forms with an upload in them append it.
        let entry = leavesEntry ? " \(Self.entrySentence)" : ""
        if uploads <= 0 {
            title = exports == 1
                ? "An export is still running." : "\(exports) exports are still running."
            body = exports == 1
                ? "Quitting now throws it away. The recording it came from is untouched."
                : "Quitting now throws them away. The recordings they came from are untouched."
            wait = "Wait for Export"
        } else if exports <= 0 {
            title = uploads == 1
                ? "An upload to YouTube is still running."
                : "\(uploads) uploads to YouTube are still running."
            body = (uploads == 1
                ? "Quitting now stops it. The clip stays on this Mac."
                : "Quitting now stops them. The clips stay on this Mac.") + entry
            wait = "Wait for Upload"
        } else {
            // Each kind in its own number: one export and two uploads is neither all singular
            // nor all plural.
            title = "\(exports == 1 ? "An export" : "\(exports) exports") and "
                + "\(uploads == 1 ? "an upload" : "\(uploads) uploads") are still running."
            body = "Quitting now throws the \(exports == 1 ? "export" : "exports") away and stops "
                + "the \(uploads == 1 ? "upload" : "uploads"). "
                + (exports == 1 ? "The recording is untouched." : "The recordings are untouched.")
                + entry
            wait = "Wait for Both"
        }
    }

    /// The second line of `Stop recording and quit?`. That quit finishes the recording and the
    /// exports but stops uploads without waiting — a transfer can outlast any quit — so it says so.
    public static func stopRecordingBody(uploads: Int, leavesEntry: Bool) -> String {
        let saved = "Your recording will be saved first."
        guard uploads > 0 else { return saved }
        let stopped = uploads == 1
            ? "The upload to YouTube is stopped." : "The uploads to YouTube are stopped."
        return [saved, stopped, leavesEntry ? entrySentence : nil].compactMap { $0 }
            .joined(separator: " ")
    }
}
