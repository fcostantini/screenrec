import CoreGraphics
import ScreenCaptureKit
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
        #expect(config.content == .display(.main))
        #expect(config.microphone == .none)
        #expect(config.frameRateCap == 60)
        #expect(config.quality == .balanced)
    }

    @Test func storesExplicitSelections() {
        let config = CaptureConfiguration(
            content: .display(.id(7)), microphone: .device(id: "MIC-1"), frameRateCap: 30, quality: .high)
        #expect(config.content == .display(.id(7)))
        #expect(config.microphone == .device(id: "MIC-1"))
        #expect(config.frameRateCap == 30)
        #expect(config.quality == .high)
    }

    @Test func storesAppContent() {
        let config = CaptureConfiguration(content: .app(bundleID: "com.example.app"))
        #expect(config.content == .app(bundleID: "com.example.app"))
    }

    // MARK: preset parsing (CLI/settings literals)

    @Test func qualityPresetParsesLiterals() {
        #expect(QualityPreset(rawValue: "efficient") == .efficient)
        #expect(QualityPreset(rawValue: "balanced") == .balanced)
        #expect(QualityPreset(rawValue: "high") == .high)
        #expect(QualityPreset(rawValue: "ultra") == nil)
        #expect(QualityPreset.allCases.count == 3)
    }

    // MARK: system audio (ADR-019)

    @Test func systemAudioIsCapturedUnlessTurnedOff() {
        // The stream-level switch: `capturesAudio` is what decides whether SCK opens an audio
        // tap at all, so the flag has to reach it — not just the writer.
        let on = SCStreamConfiguration()
        on.applyAudioCapture(systemAudio: true, microphoneID: nil)
        #expect(on.capturesAudio)
        #expect(on.sampleRate == 48_000 && on.channelCount == 2)
        #expect(on.excludesCurrentProcessAudio)

        let off = SCStreamConfiguration()
        off.applyAudioCapture(systemAudio: false, microphoneID: "device-id")
        #expect(!off.capturesAudio)
        // The mic is independent: system audio off must not disturb it.
        #expect(off.captureMicrophone)
        #expect(off.microphoneCaptureDeviceID == "device-id")
    }

    @Test func configurationDefaultsToCapturingSystemAudio() {
        #expect(CaptureConfiguration().capturesSystemAudio)
        #expect(!CaptureConfiguration(capturesSystemAudio: false).capturesSystemAudio)
    }
}
