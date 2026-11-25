import CoreGraphics
import Testing

@testable import AppShell

/// How large the Preview window opens when the user has not placed it (M43-T1).
@Suite struct PreviewLayoutTests {

    /// A screen whose 70 % share, less the caption row, is a 1400 × 810 box for the picture.
    private let visible = CGSize(width: 2000, height: 1200)

    @Test func aFullDisplayRecordingKeepsItsShapeInsideTheScreenShare() {
        // 16:10 into 1400 × 810: the height binds, and the width follows the clip's shape.
        let picture = PreviewLayout.pictureSize(
            clip: CGSize(width: 4112, height: 2570), visible: visible)
        #expect(picture == CGSize(width: 1296, height: 810))
    }

    @Test func aWideClipIsBoundByItsWidth() {
        let picture = PreviewLayout.pictureSize(
            clip: CGSize(width: 5600, height: 1400), visible: visible)
        #expect(picture == CGSize(width: 1400, height: 350))
    }

    @Test func aSmallClipIsNotBlownUpPastAPointPerPixel() {
        let picture = PreviewLayout.pictureSize(
            clip: CGSize(width: 800, height: 600), visible: visible)
        #expect(picture == CGSize(width: 800, height: 600))
    }

    @Test func nothingOpensUnderTheFloor() {
        let tiny = PreviewLayout.pictureSize(clip: CGSize(width: 200, height: 100), visible: visible)
        #expect(tiny == PreviewLayout.minimumPicture)
        // A sliver keeps the dimension that clears the floor and is letterboxed in the other.
        let sliver = PreviewLayout.pictureSize(
            clip: CGSize(width: 1200, height: 100), visible: visible)
        #expect(sliver == CGSize(width: 1200, height: PreviewLayout.minimumPicture.height))
    }

    @Test func aClipWhoseSizeCannotBeReadOpensAtTheFloor() {
        let floor = PreviewLayout.minimumPicture
        #expect(PreviewLayout.pictureSize(clip: nil, visible: visible) == floor)
        #expect(PreviewLayout.pictureSize(clip: .zero, visible: visible) == floor)
        // No screen to measure against is the same answer, not a negative size.
        #expect(
            PreviewLayout.pictureSize(clip: CGSize(width: 800, height: 600), visible: .zero)
                == floor)
    }

    @Test func theWindowIsThePicturePlusTheCaptionRow() {
        let clip = CGSize(width: 800, height: 600)
        let content = PreviewLayout.contentSize(clip: clip, visible: visible)
        #expect(content == CGSize(width: 800, height: 600 + PreviewLayout.captionHeight))
    }

    // MARK: - Where a moved window reopens

    /// AppKit's coordinates: the origin is the bottom-left and y runs up, so a top-left of
    /// (300, 1000) with a 400-tall window puts its bottom edge at 600.
    private let screen = CGRect(x: 0, y: 0, width: 2000, height: 1200)

    @Test func aWindowThatFitsHangsFromWhereItWasLeft() {
        let frame = PreviewLayout.frame(
            topLeft: CGPoint(x: 300, y: 1000), size: CGSize(width: 600, height: 400), visible: screen)
        #expect(frame == CGRect(x: 300, y: 600, width: 600, height: 400))
    }

    /// A small clip was left near the corner; a larger one opened there would run off the screen.
    @Test func aLargerWindowIsSlidBackInsideTheScreen() {
        let frame = PreviewLayout.frame(
            topLeft: CGPoint(x: 1700, y: 350), size: CGSize(width: 1300, height: 800),
            visible: screen)
        #expect(frame == CGRect(x: 700, y: 0, width: 1300, height: 800))
    }

    @Test func aWindowLeftAboveOrLeftOfTheScreenIsBroughtIn() {
        let frame = PreviewLayout.frame(
            topLeft: CGPoint(x: -200, y: 1500), size: CGSize(width: 600, height: 400),
            visible: screen)
        #expect(frame == CGRect(x: 0, y: 800, width: 600, height: 400))
    }

    /// Too large to fit at all: the title bar stays reachable, and the overflow goes right and down.
    @Test func aWindowLargerThanTheScreenKeepsItsTopLeftCornerOnIt() {
        let frame = PreviewLayout.frame(
            topLeft: CGPoint(x: 500, y: 700), size: CGSize(width: 2400, height: 1500),
            visible: screen)
        #expect(frame == CGRect(x: 0, y: -300, width: 2400, height: 1500))
    }

    /// A second display's usable area does not start at the origin.
    @Test func theScreenNeedNotStartAtTheOrigin() {
        let second = CGRect(x: 2000, y: 100, width: 1000, height: 800)
        let frame = PreviewLayout.frame(
            topLeft: CGPoint(x: 2900, y: 950), size: CGSize(width: 400, height: 300),
            visible: second)
        #expect(frame == CGRect(x: 2600, y: 600, width: 400, height: 300))
    }
}
