import CoreGraphics
import Foundation
import RecorderCore
import Testing

@testable import AppCore

/// The drag→pixels mapping (M26-T2). The preview letterboxes its source, so every one of these is
/// really asking the same question: was the rectangle measured against the video or against the view?
@Suite struct CropGeometryTests {

    /// The dev display in the Trim window's 480 × 300 preview: 4112 × 2570 is wider than 16:10, so
    /// the video is letterboxed top and bottom, not pillarboxed.
    private let source = CGSize(width: 4112, height: 2570)
    private let view = CGSize(width: 480, height: 300)

    @Test func theVideoIsFittedAndCentredInThePreview() {
        let rect = CropGeometry.videoRect(sourceSize: source, in: view)
        #expect(rect.width == 480)  // width-limited: 480/4112 < 300/2570
        #expect(abs(rect.height - 299.95) < 0.1)
        #expect(rect.minX == 0)
        #expect(abs(rect.minY - (view.height - rect.height) / 2) < 0.001)
        // A tall source pillarboxes instead — the same code, the other axis.
        let portrait = CropGeometry.videoRect(sourceSize: CGSize(width: 1000, height: 2000), in: view)
        #expect(portrait.height == 300)
        #expect(portrait.width == 150)
        #expect(portrait.minX == 165)
    }

    @Test func aDragBecomesTheSourcePixelsUnderIt() {
        let video = CropGeometry.videoRect(sourceSize: source, in: view)
        // The middle half of the video, measured from the video's own origin.
        let drag = CGRect(
            x: video.minX + video.width / 4, y: video.minY + video.height / 4,
            width: video.width / 2, height: video.height / 2)
        let crop = try? #require(
            CropGeometry.crop(fromViewRect: drag, sourceSize: source, viewSize: view))
        #expect(crop?.x == 1028)  // 4112 / 4
        #expect(crop?.width == 2056)  // 4112 / 2
        #expect(abs((crop?.y ?? 0) - 642) <= 1)  // 2570 / 4, ± the even rounding
        #expect(abs((crop?.height ?? 0) - 1284) <= 2)
    }

    @Test func aDragIsTheSameRectangleDrawnInAnyDirection() {
        let downRight = CropGeometry.crop(
            fromViewRect: CGRect(x: 100, y: 60, width: 200, height: 120),
            sourceSize: source, viewSize: view)
        // The same two corners, dragged bottom-right to top-left.
        let upLeft = CropGeometry.crop(
            fromViewRect: CGRect(x: 300, y: 180, width: -200, height: -120),
            sourceSize: source, viewSize: view)
        #expect(downRight == upLeft)
    }

    @Test func aRoundTripThroughTheViewLandsWhereItStarted() {
        // What the band drawn on screen must agree with: the crop is held in pixels and converted
        // back for drawing, so the two directions have to be inverses.
        let crop = CropRect(x: 400, y: 300, width: 1600, height: 1000)
        let rect = CropGeometry.viewRect(for: crop, sourceSize: source, viewSize: view)
        let back = CropGeometry.crop(fromViewRect: rect, sourceSize: source, viewSize: view)
        #expect(abs((back?.x ?? 0) - crop.x) <= 2)
        #expect(abs((back?.y ?? 0) - crop.y) <= 2)
        #expect(abs((back?.width ?? 0) - crop.width) <= 4)
        #expect(abs((back?.height ?? 0) - crop.height) <= 4)
    }

    @Test func aDragOutsideTheVideoIsClampedRatherThanRefused() {
        // The letterbox bars are inside the view but outside the video. A drag that starts in one
        // must still crop — clamped to the frame — rather than vanish.
        let overshooting = CGRect(x: -50, y: -50, width: 600, height: 500)
        let crop = try? #require(
            CropGeometry.crop(fromViewRect: overshooting, sourceSize: source, viewSize: view))
        #expect(crop?.x == 0)
        #expect(crop?.y == 0)
        #expect(crop?.width == 4112)
        #expect(crop?.height == 2570)
    }

    @Test func aDragThatMissesOrIsTooSmallIsNoCrop() {
        // Entirely inside the letterbox bar, above the video.
        let bar = CropGeometry.videoRect(sourceSize: source, in: view).minY
        #expect(CropGeometry.crop(
            fromViewRect: CGRect(x: 10, y: 0, width: 100, height: bar / 2),
            sourceSize: source, viewSize: view) == nil)
        // A click, not a drag.
        #expect(CropGeometry.crop(
            fromViewRect: CGRect(x: 100, y: 100, width: 0, height: 0),
            sourceSize: source, viewSize: view) == nil)
        // Nothing is known about the source yet (M16-T2: no geometry, no figure).
        #expect(CropGeometry.crop(
            fromViewRect: CGRect(x: 10, y: 10, width: 100, height: 100),
            sourceSize: .zero, viewSize: view) == nil)
    }
}
