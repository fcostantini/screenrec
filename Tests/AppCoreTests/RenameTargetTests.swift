import Foundation
import Testing
@testable import AppCore

/// The pure naming rules of Rename… (M12-T2). Collisions are the caller's to resolve
/// (`Exporter.availableURL`), so these only pin the target computation and its no-op cases.
@Suite struct RenameTargetTests {

    private static func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Movies/\(name)")
    }

    @Test func keepsTheExtensionAndFolderChangingOnlyTheBaseName() {
        let target = RenameTarget.compute(for: Self.url("Recording 1.mp4"), newBaseName: "demo")
        #expect(target == Self.url("demo.mp4"))
    }

    @Test func trimsSurroundingWhitespace() {
        let target = RenameTarget.compute(for: Self.url("clip.gif"), newBaseName: "  final cut  ")
        #expect(target == Self.url("final cut.gif"))
    }

    @Test func aBlankNameIsANoOp() {
        #expect(RenameTarget.compute(for: Self.url("clip.mov"), newBaseName: "   ") == nil)
    }

    @Test func theSameNameIsANoOp() {
        // Re-entering the current name shouldn't move the file onto itself.
        #expect(RenameTarget.compute(for: Self.url("clip.mov"), newBaseName: "clip") == nil)
    }

    @Test func aNameWithAPathSeparatorIsRejected() {
        // A rename is a name, not a move — "../evil" must not escape the folder.
        #expect(RenameTarget.compute(for: Self.url("clip.mov"), newBaseName: "../evil") == nil)
    }

    @Test func anExtensionlessFileGainsNoTrailingDot() {
        let target = RenameTarget.compute(for: URL(fileURLWithPath: "/Movies/README"), newBaseName: "notes")
        #expect(target == URL(fileURLWithPath: "/Movies/notes"))
    }
}
