import Foundation
import Testing
@testable import AppCore
import RecorderCore

@Suite struct MenuHeaderTests {

    @Test func recordingDetailNamesTheCodec() {
        // docs/06's recording header: `<size> · HEVC`.
        #expect(MenuHeader.recordingDetail(bytes: 0).hasSuffix(" · HEVC"))
        #expect(MenuHeader.recordingDetail(bytes: 41_200_000).contains("MB"))
    }

    @Test func recordingDetailTreatsAMissingFileAsZeroNotNegative() {
        #expect(MenuHeader.recordingDetail(bytes: -1) == MenuHeader.recordingDetail(bytes: 0))
    }

    @Test func readyReadsReady() {
        #expect(MenuHeader.idleStatus(.ready) == "Ready")
    }

    @Test(arguments: [
        RecordingReadiness.needsScreenRecording,
        .needsMicrophone,
        .blocked(reason: "Screen Recording is turned off for this app. Turn it on in System "
            + "Settings → Privacy & Security → Screen & System Audio Recording, then quit and "
            + "reopen the app."),
    ])
    func everyBlockedVerdictCollapsesToOneShortPhrase(readiness: RecordingReadiness) {
        // docs/06 item 1 gives the header one short phrase. `blocked` carries a full remedy
        // sentence for the onboarding window (M4-T3) — putting that in a disabled menu row would
        // blow out the menu's width to say something the user can't act on from there.
        #expect(MenuHeader.idleStatus(readiness) == "Permissions needed…")
    }

    @Test func recordingsFolderIsHomeRelative() {
        // Built from NSHomeDirectory so the abbreviation has the same home to match against.
        let movies = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        #expect(MenuHeader.recordingsFolder(movies) == "~/Movies")
    }

    @Test func recordingsFolderOutsideHomeStaysAbsolute() {
        // An external drive can't be shortened — the user sees exactly where it goes.
        #expect(MenuHeader.recordingsFolder(URL(fileURLWithPath: "/Volumes/Ext/Recordings"))
            == "/Volumes/Ext/Recordings")
    }

    @Test func recordingsFolderKeepsOnlyTheTailOfADeepPath() {
        // A menu sizes itself to its widest row: a deep path would stretch the whole menu
        // across the screen. The kept tail is the part the user actually chose.
        let deep = URL(fileURLWithPath:
            "/private/tmp/claude-501/some-sandbox-name/0314-0040-4615/scratchpad/replays")
        let shown = MenuHeader.recordingsFolder(deep)
        // The contract: within budget, elision marked, the chosen folder's tail intact —
        // how many ancestors fit is the algorithm's business.
        #expect(shown.hasPrefix("…/"))
        #expect(shown.hasSuffix("/scratchpad/replays"))
        #expect(shown.count <= 41)   // budget + the ellipsis
    }

    @Test func recordingsFolderTrimsAnOversizedSingleComponent() {
        let absurd = URL(fileURLWithPath:
            "/Volumes/" + String(repeating: "x", count: 80))
        let shown = MenuHeader.recordingsFolder(absurd)
        #expect(shown.hasPrefix("…"))
        #expect(shown.count <= 41)
        #expect(shown.hasSuffix("x"))   // the end survives — the most specific part
    }
}
