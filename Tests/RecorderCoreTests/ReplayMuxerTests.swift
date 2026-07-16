import AVFoundation
import CoreMedia
import Testing

@testable import RecorderCore

/// End-to-end without a capture stream: synthesized frames go through the REAL VT encoder
/// (no TCC needed) into the rings, and the muxer writes a real file the asset APIs then judge.
struct ReplayMuxerTests {

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayMuxerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A filled pipeline: `videoSeconds` of 30 fps video through the VT encoder, matching
    /// system (planar Float32 stereo — the real SCK format) and mic (Int16 mono) PCM.
    private func makeRings(
        videoSeconds: Int, ringSeconds: Double
    ) -> (ReplayEncoder, ReplayAudioRing, ReplayAudioRing) {
        let encoder = ReplayEncoder(seconds: ringSeconds, frameRateCap: 30)
        let system = ReplayAudioRing(source: .systemAudio, seconds: ringSeconds)
        let mic = ReplayAudioRing(source: .microphone, seconds: ringSeconds)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2, planarFloat32: true)
        let micFormat = makeAudioFormat(sampleRate: 24_000, channels: 1)

        encodeSyntheticFrames(into: encoder, count: videoSeconds * 30)
        // 0.1 s audio buffers covering the same span as the video.
        for index in 0..<(videoSeconds * 10) {
            system.consume(
                makeAudioSampleBuffer(
                    format: systemFormat, frames: 4800,
                    pts: CMTime(value: CMTimeValue(index * 4800), timescale: 48_000)),
                type: .systemAudio)
            mic.consume(
                makeAudioSampleBuffer(
                    format: micFormat, frames: 2400,
                    pts: CMTime(value: CMTimeValue(index * 2400), timescale: 24_000)),
                type: .microphone)
        }
        return (encoder, system, mic)
    }

    private func save(_ muxer: ReplayMuxer) async -> Result<ReplayMuxer.SavedReplay, Error>? {
        await withCheckedContinuation { continuation in
            let accepted = muxer.requestSave { continuation.resume(returning: $0) }
            if !accepted { continuation.resume(returning: nil) }
        }
    }

    @Test func writesPlayableClipWithThreeTracks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (encoder, system, mic) = makeRings(videoSeconds: 4, ringSeconds: 60)
        let muxer = ReplayMuxer(
            encoder: encoder, systemRing: system, microphoneRing: mic,
            seconds: 60, outputDirectory: directory)

        let saved = try #require(try await save(muxer)?.get())
        #expect(saved.url.lastPathComponent.hasPrefix("Replay "))
        // Ring younger than the 60 s window → the short-ring fallback: everything from the
        // oldest keyframe, ~4 s.
        #expect(saved.duration > 3.0 && saved.duration < 4.2)

        let asset = AVURLAsset(url: saved.url)
        let tracks = try await asset.load(.tracks)
        let video = tracks.filter { $0.mediaType == .video }
        let audio = tracks.filter { $0.mediaType == .audio }
        #expect(video.count == 1)
        #expect(audio.count == 2)
        for track in video {
            let formats = try await track.load(.formatDescriptions)
            #expect(CMFormatDescriptionGetMediaSubType(formats[0]) == kCMVideoCodecType_HEVC)
        }
        for track in audio {
            let formats = try await track.load(.formatDescriptions)
            #expect(CMFormatDescriptionGetMediaSubType(formats[0]) == kAudioFormatMPEG4AAC)
        }
        // Rebased to zero: the asset's duration matches the clip span, not the source pts range.
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - saved.duration) < 0.35)
    }

    @Test func concurrentSaveCoalesces() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (encoder, system, mic) = makeRings(videoSeconds: 3, ringSeconds: 60)
        let muxer = ReplayMuxer(
            encoder: encoder, systemRing: system, microphoneRing: mic,
            seconds: 60, outputDirectory: directory)

        // Fire the second request while the first mux is (almost certainly) still writing;
        // even if the first finished, at most two files result and neither is torn — but the
        // accepted flags must never both be false.
        var accepted = 0
        let done = DispatchSemaphore(value: 0)
        for _ in 0..<2 {
            if muxer.requestSave(completion: { _ in done.signal() }) { accepted += 1 }
        }
        for _ in 0..<accepted { done.wait() }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(accepted >= 1)
        #expect(files.count == accepted)
    }

    @Test func emptyRingsReportNothingBuffered() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = ReplayEncoder(seconds: 60, frameRateCap: 30)
        let system = ReplayAudioRing(source: .systemAudio, seconds: 60)
        let muxer = ReplayMuxer(
            encoder: encoder, systemRing: system, microphoneRing: nil,
            seconds: 60, outputDirectory: directory)

        let result = await save(muxer)
        var failure: Error?
        if case .failure(let error) = result { failure = error }
        #expect(failure as? ReplayMuxerError == .nothingBuffered)
        // No reservation litter either.
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true)
    }

    /// The screen goes still partway through the window: audio outlives video, and the last
    /// frame must be re-appended at the clip end (docs/02 §5's tail patch) so the file spans
    /// the true last N seconds instead of ending at the last screen change.
    @Test func staticTailFreezesVideoToTheClipEnd() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = ReplayEncoder(seconds: 60, frameRateCap: 30)
        let system = ReplayAudioRing(source: .systemAudio, seconds: 60)
        encodeSyntheticFrames(into: encoder, count: 60)  // video stops at 2 s
        let format = makeAudioFormat(sampleRate: 48_000, channels: 2, planarFloat32: true)
        for index in 0..<60 {  // audio keeps rolling to 6 s
            system.consume(
                makeAudioSampleBuffer(
                    format: format, frames: 4800,
                    pts: CMTime(value: CMTimeValue(index * 4800), timescale: 48_000)),
                type: .systemAudio)
        }
        let muxer = ReplayMuxer(
            encoder: encoder, systemRing: system, microphoneRing: nil,
            seconds: 60, outputDirectory: directory)

        let saved = try #require(try await save(muxer)?.get())
        #expect(saved.duration > 5.5 && saved.duration < 6.2)
        let asset = AVURLAsset(url: saved.url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 5.5 && duration < 6.5)
    }

    /// The screen sat still for the entire window: the clip must still be the last N seconds
    /// (anchored at the audio clock), with the stale GOP frozen at the top — not a minutes-long
    /// file and not minute-old content.
    @Test func fullyStaleVideoWindowSavesTheLastAudioSeconds() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = ReplayEncoder(seconds: 10, frameRateCap: 30)
        let system = ReplayAudioRing(source: .systemAudio, seconds: 10)
        encodeSyntheticFrames(into: encoder, count: 60)  // video ends at 2 s
        let format = makeAudioFormat(sampleRate: 48_000, channels: 2, planarFloat32: true)
        for index in 300..<600 {  // audio rolls 30 s → 60 s, far past the video
            system.consume(
                makeAudioSampleBuffer(
                    format: format, frames: 4800,
                    pts: CMTime(value: CMTimeValue(index * 4800), timescale: 48_000)),
                type: .systemAudio)
        }
        let muxer = ReplayMuxer(
            encoder: encoder, systemRing: system, microphoneRing: nil,
            seconds: 10, outputDirectory: directory)

        let saved = try #require(try await save(muxer)?.get())
        #expect(saved.duration > 9.5 && saved.duration < 10.5)
        let asset = AVURLAsset(url: saved.url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 9.5 && duration < 11.0)
    }

    @Test func clipTrimsToRequestedWindow() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 6 s buffered, 2 s window → the clip must be ~2 s (+ ≤1 s keyframe alignment), not 6.
        let (encoder, system, mic) = makeRings(videoSeconds: 6, ringSeconds: 10)
        let muxer = ReplayMuxer(
            encoder: encoder, systemRing: system, microphoneRing: mic,
            seconds: 2, outputDirectory: directory)

        let saved = try #require(try await save(muxer)?.get())
        #expect(saved.duration >= 1.9 && saved.duration <= 3.1)

        let asset = AVURLAsset(url: saved.url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration >= 1.9 && duration <= 3.4)
    }
}
