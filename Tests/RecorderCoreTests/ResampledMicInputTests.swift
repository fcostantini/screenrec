import AVFoundation
import CoreMedia
import Testing
@testable import RecorderCore

/// The M8-T1 contract: any device format in, exactly one fixed format out, PTS preserved.
@Suite struct ResampledMicInputTests {

    private var target: AudioStreamBasicDescription {
        ResampledMicInput.targetFormat.streamDescription.pointee
    }

    private func asbd(of buffer: CMSampleBuffer) -> AudioStreamBasicDescription? {
        CMSampleBufferGetFormatDescription(buffer).flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
    }

    @Test func airPodsRate24kDoublesItsSampleCount() {
        let input = ResampledMicInput()
        let pts = CMTime(value: 3, timescale: 100)
        let buffer = makeAudioSampleBuffer(
            format: makeAudioFormat(sampleRate: 24_000, channels: 1, planarFloat32: true),
            frames: 480, pts: pts)                                     // 20 ms @ 24 kHz

        let converted = input.convert(buffer)
        #expect(converted.map(CMSampleBufferGetNumSamples) == 960)     // 20 ms @ 48 kHz, exact
        #expect(converted.map(CMSampleBufferGetPresentationTimeStamp) == pts)
        #expect(converted.flatMap(asbd(of:))?.hasSameIdentity(as: target) == true)
    }

    @Test func a48kInt16BufferKeepsItsCountAndGainsTheTargetFormat() {
        let input = ResampledMicInput()
        let pts = CMTime(value: 7, timescale: 100)
        let buffer = makeAudioSampleBuffer(
            format: makeAudioFormat(sampleRate: 48_000, channels: 1),  // 16-bit interleaved
            frames: 960, pts: pts)

        let converted = input.convert(buffer)
        #expect(converted.map(CMSampleBufferGetNumSamples) == 960)
        #expect(converted.map(CMSampleBufferGetPresentationTimeStamp) == pts)
        #expect(converted.flatMap(asbd(of:))?.hasSameIdentity(as: target) == true)
    }

    @Test func stereoDownmixesToTheMonoTarget() {
        let input = ResampledMicInput()
        let buffer = makeAudioSampleBuffer(
            format: makeAudioFormat(sampleRate: 48_000, channels: 2), frames: 960, pts: .zero)

        let converted = input.convert(buffer)
        #expect(converted.flatMap(asbd(of:))?.mChannelsPerFrame == 1)
        #expect(converted.map(CMSampleBufferGetNumSamples) == 960)
    }

    @Test func aTargetFormatBufferPassesThroughUntouched() {
        let input = ResampledMicInput()
        // planarFloat32 mono @48 kHz is byte-for-byte the target's identity fields.
        let buffer = makeAudioSampleBuffer(
            format: makeAudioFormat(sampleRate: 48_000, channels: 1, planarFloat32: true),
            frames: 960, pts: .zero)
        #expect(input.convert(buffer) === buffer)
    }

    @Test func aMidStreamDeviceFlipStaysContinuousAndFixed() {
        // The M8 point: a 24 kHz → 48 kHz device flip yields one uninterrupted fixed-format
        // stream (docs/02 §4).
        let input = ResampledMicInput()
        let airPods = makeAudioFormat(sampleRate: 24_000, channels: 1, planarFloat32: true)
        let builtIn = makeAudioFormat(sampleRate: 48_000, channels: 1, planarFloat32: true)

        var lastPTS = CMTime.negativeInfinity
        for index in 0..<20 {
            let device = index < 10 ? airPods : builtIn
            let frames = index < 10 ? 480 : 960                        // 20 ms each
            let pts = CMTime(value: CMTimeValue(index * 20), timescale: 1000)
            guard let converted = input.convert(
                makeAudioSampleBuffer(format: device, frames: frames, pts: pts)) else {
                Issue.record("conversion failed at buffer \(index)")
                return
            }
            #expect(asbd(of: converted)?.hasSameIdentity(as: target) == true)
            #expect(CMSampleBufferGetNumSamples(converted) == 960)
            let outPTS = CMSampleBufferGetPresentationTimeStamp(converted)
            #expect(CMTimeCompare(outPTS, lastPTS) > 0)
            lastPTS = outPTS
        }
    }

    @Test func aFlipThroughTheResamplerStillFinalizesOneMicTrack() async throws {
        // Composition with MovieRecorder: a device flip mid-recording finalizes with video +
        // system + ONE full-length mic track.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resampled-mic-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }

        let input = ResampledMicInput()
        let recorder = try MovieRecorder(
            outputURL: url, frameRate: 10, preset: .efficient, includesMicrophone: true)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        let airPods = makeAudioFormat(sampleRate: 24_000, channels: 1, planarFloat32: true)
        let builtIn = makeAudioFormat(sampleRate: 48_000, channels: 1, planarFloat32: true)
        let frameDuration = CMTime(value: 1, timescale: 10)

        for index in 0..<40 {
            let pts = CMTime(value: CMTimeValue(index), timescale: 10)
            recorder.consume(
                makeVideoSampleBuffer(width: 640, height: 400, pts: pts, duration: frameDuration),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat, frames: 4800, pts: pts),
                type: .systemAudio)
            let mic = makeAudioSampleBuffer(
                format: index < 20 ? airPods : builtIn,
                frames: index < 20 ? 2400 : 4800, pts: pts)
            if let normalized = input.convert(mic) {
                recorder.consume(normalized, type: .microphone)
            }
        }

        let asset = AVURLAsset(url: try await recorder.finish())
        let tracks = try await asset.load(.tracks)
        #expect(tracks.filter { $0.mediaType == .video }.count == 1)
        #expect(tracks.filter { $0.mediaType == .audio }.count == 2)
        // The mic track spans the flip: nothing was dropped or fail-stopped at the boundary.
        if let micTrack = tracks.filter({ $0.mediaType == .audio }).last {
            let range = try await micTrack.load(.timeRange)
            #expect(range.duration.seconds > 3.5)
        }
    }
}
