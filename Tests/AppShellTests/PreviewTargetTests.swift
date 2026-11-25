import Foundation
import Testing

@testable import AppShell

/// What the Preview window is asked to play, and whether that is a new clip (M43-T1).
@MainActor
@Suite struct PreviewTargetTests {

    private let a = URL(fileURLWithPath: "/tmp/a.mov")
    private let b = URL(fileURLWithPath: "/tmp/b.mov")

    @Test func aSecondPlayOfTheSameFileIsAPressButNotANewClip() {
        let target = PreviewTarget()
        target.play(a)
        let clip = target.clip
        target.play(a)
        #expect(target.clip == clip)
        #expect(target.plays == 2)
    }

    @Test func anotherFileIsANewClip() {
        let target = PreviewTarget()
        target.play(a)
        let clip = target.clip
        target.play(b)
        #expect(target.clip != clip)
        #expect(target.url == b)
    }

    /// The player holds the file, not its name: a rename must not reload it, and neither must the
    /// next `Play` on the row that now carries the new name.
    @Test func aRenameKeepsTheClipAndSoDoesPlayingItUnderItsNewName() {
        let target = PreviewTarget()
        target.play(a)
        let clip = target.clip
        let plays = target.plays
        target.renamed(to: b)
        #expect(target.url == b)
        #expect(target.clip == clip)
        #expect(target.plays == plays)
        target.play(b)
        #expect(target.clip == clip)
    }
}
