import Foundation
import Testing
@testable import RecorderCore

/// Which derive actions a file can take (M24-T5). One rule for the menu and anything after it —
/// a wrong answer here either hides a working action or offers one that ends in a failure notice.
@Suite struct DeriveOptionsTests {

    private func options(_ name: String) -> DeriveOptions {
        DeriveOptions(for: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    @Test func aRecordingTakesEveryDerive() {
        let mov = options("Recording.mov")
        #expect(mov.canExportToMP4)
        #expect(mov.canSaveAsGIF)
        #expect(mov.canTrim)
    }

    @Test func anExportIsNotOfferedAnotherExport() {
        // The complaint: re-encoding what's already encoded, quietly. GIF and Trim still apply —
        // both make something the .mp4 isn't.
        for name in ["Clip.mp4", "Clip.m4v", "Clip.MP4"] {
            let mp4 = options(name)
            #expect(!mp4.canExportToMP4, "\(name) should not offer another MP4")
            #expect(mp4.canSaveAsGIF)
            #expect(mp4.canTrim)
        }
    }

    @Test func aGifTakesNoDeriveAtAllBecauseNothingCanReadIt() {
        // Measured: AVURLAsset reports isReadable false, no video tracks, duration -1 for a GIF,
        // so all three rows would end in a failure notice.
        let gif = options("Loop.gif")
        #expect(!gif.canExportToMP4)
        #expect(!gif.canSaveAsGIF)
        #expect(!gif.canTrim)
        #expect(!gif.hasAny)          // …and the menu drops the divider with them
    }

    @Test func anUnknownExtensionIsTreatedAsAMovie() {
        // Hiding an action that would have worked is worse than an exporter failing honestly.
        let odd = options("Something.mkv")
        #expect(odd.canExportToMP4)
        #expect(odd.canTrim)
        #expect(odd.hasAny)
    }
}
