import CoreGraphics
import Testing
@testable import RecorderCore

@Suite struct CaptureConfigurationTests {

    // MARK: pixel math

    @Test func pixelDimensionsAppliesRetinaScale() {
        // The dev display: 2056×1285 points @2× → 4112×2570 pixels (docs/02 §1).
        let (width, height) = CaptureConfiguration.pixelDimensions(
            pointSize: CGSize(width: 2056, height: 1285), pointPixelScale: 2)
        #expect(width == 4112)
        #expect(height == 2570)
    }

    @Test func pixelDimensionsAtOneToOne() {
        let (width, height) = CaptureConfiguration.pixelDimensions(
            pointSize: CGSize(width: 1920, height: 1080), pointPixelScale: 1)
        #expect(width == 1920)
        #expect(height == 1080)
    }

    @Test func pixelDimensionsRoundsToWholePixels() {
        let (width, height) = CaptureConfiguration.pixelDimensions(
            pointSize: CGSize(width: 1000.4, height: 500.1), pointPixelScale: 2)
        #expect(width == 2001)   // 2000.8 → 2001
        #expect(height == 1000)  // 1000.2 → 1000
    }

    // MARK: defaults

    @Test func defaultsAreMainDisplayNoMic60fpsBalanced() {
        let config = CaptureConfiguration()
        #expect(config.display == .main)
        #expect(config.microphone == .none)
        #expect(config.frameRateCap == 60)
        #expect(config.quality == .balanced)
    }

    @Test func storesExplicitSelections() {
        let config = CaptureConfiguration(
            display: .id(7), microphone: .device(id: "MIC-1"), frameRateCap: 30, quality: .high)
        #expect(config.display == .id(7))
        #expect(config.microphone == .device(id: "MIC-1"))
        #expect(config.frameRateCap == 30)
        #expect(config.quality == .high)
    }

    // MARK: preset parsing (CLI/settings literals)

    @Test func qualityPresetParsesLiterals() {
        #expect(QualityPreset(rawValue: "efficient") == .efficient)
        #expect(QualityPreset(rawValue: "balanced") == .balanced)
        #expect(QualityPreset(rawValue: "high") == .high)
        #expect(QualityPreset(rawValue: "ultra") == nil)
        #expect(QualityPreset.allCases.count == 3)
    }
}
