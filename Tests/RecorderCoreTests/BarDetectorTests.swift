import CoreGraphics
import Foundation
import Testing

@testable import RecorderCore

/// The letterbox detector (M26-T3). Frames are built in memory, so these run without a fixture on
/// disk — the calibration against *real* bars is the CLI leg, and against a real capture is open.
@Suite struct BarDetectorTests {

    @Test func findsBarsAndReturnsWhatIsBetweenThem() throws {
        let frame = try #require(Self.image(width: 200, height: 120) { x, y in
            (y < 20 || y >= 100) ? 64 : Self.content(x, y)
        })
        #expect(BarDetector.bars(in: frame) == CropRect(x: 0, y: 20, width: 200, height: 80))
    }

    @Test func theBarsLevelIsNeverTested() throws {
        // Bars encoded at luma 64 decode to 73 (docs/07), so a detector keyed to "black-ish" would
        // miss its own fixture. These are mid-grey and light-grey — both must be found.
        for level: UInt8 in [30, 73, 128, 200] {
            let frame = try #require(Self.image(width: 160, height: 100) { x, y in
                (y < 15 || y >= 85) ? level : Self.content(x, y)
            })
            #expect(
                BarDetector.bars(in: frame) == CropRect(x: 0, y: 15, width: 160, height: 70),
                "level \(level)")
        }
    }

    @Test func findsPillarboxToo() throws {
        let frame = try #require(Self.image(width: 200, height: 120) { x, y in
            (x < 30 || x >= 170) ? 64 : Self.content(x, y)
        })
        #expect(BarDetector.bars(in: frame) == CropRect(x: 30, y: 0, width: 140, height: 120))
    }

    @Test func aFrameWithNoBarsDetectsNothing() throws {
        // The control the task was filed with: without it, a detector that always fires looks like
        // it works.
        let frame = try #require(Self.image(width: 200, height: 120) { x, y in Self.content(x, y) })
        #expect(BarDetector.bars(in: frame) == nil)
    }

    @Test func aFrameFlatEnoughToSwallowItselfIsNotALetterbox() throws {
        // A fade to black is flat everywhere. Reading it as bars would "crop" the whole frame away.
        let frame = try #require(Self.image(width: 200, height: 120) { _, _ in 8 })
        #expect(BarDetector.bars(in: frame) == nil)
    }

    @Test func framesAgreeOnTheSmallestBarAnyOfThemShows() throws {
        // A dark scene reads like a bar, so the combine takes the most conservative answer: one
        // misleading frame can only under-crop, never eat content.
        let twenty = try #require(Self.image(width: 200, height: 120) { x, y in
            (y < 20 || y >= 100) ? 64 : Self.content(x, y)
        })
        let twelve = try #require(Self.image(width: 200, height: 120) { x, y in
            (y < 12 || y >= 108) ? 64 : Self.content(x, y)
        })
        #expect(
            BarDetector.bars(in: [twenty, twelve])
                == CropRect(x: 0, y: 12, width: 200, height: 96))
        // And one frame with no bars at all means no crop, whatever the others saw.
        let none = try #require(Self.image(width: 200, height: 120) { x, y in Self.content(x, y) })
        #expect(BarDetector.bars(in: [twenty, none]) == nil)
    }

    // MARK: - Fixtures

    /// Busy content: never flat along a row or a column, so it can't read as a bar.
    private static func content(_ x: Int, _ y: Int) -> UInt8 {
        UInt8((x &* 37 &+ y &* 91) % 256)
    }

    /// A greyscale frame from a per-pixel value.
    private static func image(
        width: Int, height: Int, value: (Int, Int) -> UInt8
    ) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let level = value(x, y)
                let offset = (y * width + x) * 4
                bytes[offset] = level
                bytes[offset + 1] = level
                bytes[offset + 2] = level
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
