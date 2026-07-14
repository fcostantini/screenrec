import Testing
@testable import RecorderCore

@Suite struct BitrateModelTests {

    // The dev display, from docs/02 §1.
    private static let devWidth = 4112
    private static let devHeight = 2570

    // MARK: docs/02 §3 reference figures

    @Test func efficientAt30FpsIsAboutFiveMbps() {
        // docs/02 §3: Efficient ≈ 5 Mbps at 4112×2570×30.
        let bitrate = BitrateModel.averageBitrate(
            width: Self.devWidth, height: Self.devHeight, frameRate: 30, preset: .efficient)
        #expect((4_500_000...5_500_000).contains(bitrate))
    }

    @Test func balancedAt60FpsIsAboutNineteenMbps() {
        // docs/02 §3: Balanced ≈ 19 Mbps at 4112×2570×60.
        let bitrate = BitrateModel.averageBitrate(
            width: Self.devWidth, height: Self.devHeight, frameRate: 60, preset: .balanced)
        #expect((18_000_000...20_000_000).contains(bitrate))
    }

    // MARK: exact formula

    @Test func balancedIsTheUndiscountedBaseline() {
        // Balanced (×1) is exactly pixels × fps × baseBitsPerPixel × hevcDiscount.
        let expected = Int((Double(Self.devWidth * Self.devHeight) * 60
            * BitrateModel.baseBitsPerPixel * BitrateModel.hevcDiscount).rounded())
        let bitrate = BitrateModel.averageBitrate(
            width: Self.devWidth, height: Self.devHeight, frameRate: 60, preset: .balanced)
        #expect(bitrate == expected)
    }

    // MARK: preset ordering & multipliers

    @Test func presetsAreStrictlyOrderedAtFixedGeometry() {
        func bitrate(_ preset: QualityPreset) -> Int {
            BitrateModel.averageBitrate(
                width: Self.devWidth, height: Self.devHeight, frameRate: 60, preset: preset)
        }
        #expect(bitrate(.efficient) < bitrate(.balanced))
        #expect(bitrate(.balanced) < bitrate(.high))
    }

    @Test func presetMultipliersMatchDocumentedRatios() {
        func bitrate(_ preset: QualityPreset) -> Double {
            Double(BitrateModel.averageBitrate(
                width: Self.devWidth, height: Self.devHeight, frameRate: 60, preset: preset))
        }
        // efficient = ½ balanced, high = 1¾ balanced (docs/02 §3).
        #expect(abs(bitrate(.efficient) / bitrate(.balanced) - 0.5) < 0.001)
        #expect(abs(bitrate(.high) / bitrate(.balanced) - 1.75) < 0.001)
    }

    // MARK: proportionality

    @Test func bitrateScalesLinearlyWithFrameRate() {
        let at30 = BitrateModel.averageBitrate(
            width: Self.devWidth, height: Self.devHeight, frameRate: 30, preset: .balanced)
        let at60 = BitrateModel.averageBitrate(
            width: Self.devWidth, height: Self.devHeight, frameRate: 60, preset: .balanced)
        #expect(at60 == at30 * 2)
    }

    @Test func bitrateScalesLinearlyWithPixelCount() {
        let single = BitrateModel.averageBitrate(
            width: 1920, height: 1080, frameRate: 60, preset: .balanced)
        let doubleWidth = BitrateModel.averageBitrate(
            width: 3840, height: 1080, frameRate: 60, preset: .balanced)
        #expect(doubleWidth == single * 2)
    }

    // MARK: degenerate geometry

    @Test func zeroDimensionYieldsZeroBitrate() {
        #expect(BitrateModel.averageBitrate(
            width: 0, height: 2570, frameRate: 60, preset: .high) == 0)
        #expect(BitrateModel.averageBitrate(
            width: 4112, height: 0, frameRate: 60, preset: .high) == 0)
    }

    @Test func modestResolutionStaysBelowLargerAtSamePreset() {
        // A 1080p frame must cost less than the full 4112×2570 frame at the same preset/fps.
        let hd = BitrateModel.averageBitrate(
            width: 1920, height: 1080, frameRate: 60, preset: .high)
        let full = BitrateModel.averageBitrate(
            width: Self.devWidth, height: Self.devHeight, frameRate: 60, preset: .high)
        #expect(hd < full)
    }
}
