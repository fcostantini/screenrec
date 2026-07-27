import AVFoundation
import CoreMedia
import Foundation

/// What one source of a self-test recording turned out to be. Four states, not two: "you turned it
/// off" and "it's broken" must not read alike (docs/03 M16-T6).
public enum SelfTestOutcome: Sendable, Equatable {
    /// It worked; `detail` names what, when naming it is useful (the device, the pixel size).
    case ok(String?)
    /// Absent because the user asked for it to be — not a problem.
    case skipped(String)
    /// Present but not right. The recording still happened.
    case warning(String)
    /// The test itself did not produce a recording.
    case failed(String)
}

/// The verdict of a five-second test recording (M16-T6): does capture actually work, from the
/// devices the user believes are selected? The setup checklist only ever proved that TCC said yes.
public struct CaptureSelfTestResult: Sendable, Equatable {
    public let screen: SelfTestOutcome
    public let systemAudio: SelfTestOutcome
    public let microphone: SelfTestOutcome
}

/// What the microphone pick amounts to at test time — resolved by the caller, since resolution
/// (device-or-nothing, 02 §1) is a capture concern the test only reports on.
public enum MicrophoneExpectation: Sendable, Equatable {
    case notSelected
    /// Picked, but not connected right now — the pick survives absence (docs/06), so this is a
    /// notice rather than a failure.
    case unavailable(name: String)
    case expected(name: String)
}

/// Runs a real recording and reports what came out. A UI over the machinery `Scripts/smoke.sh`
/// already exercises from the CLI — not a second capture path.
public enum CaptureSelfTest {
    public static let duration: TimeInterval = 5

    /// The verdict, given what the finished file contains. Pure, so every partial-pass case is
    /// testable without capturing anything.
    ///
    /// The two audio tracks are told apart by channel count: system audio is 48 kHz **stereo**, and
    /// every mic buffer is normalized to **mono** (`ResampledMicInput`).
    public static func verdict(
        videoPixelSize: CGSize?,
        hasStereoAudioTrack: Bool,
        hasMonoAudioTrack: Bool,
        systemAudioRequested: Bool,
        microphone: MicrophoneExpectation,
        microphonePeak: Float
    ) -> CaptureSelfTestResult {
        let screen: SelfTestOutcome = if let videoPixelSize, videoPixelSize.width > 0 {
            .ok("\(Int(videoPixelSize.width)) × \(Int(videoPixelSize.height))")
        } else {
            .failed("nothing was recorded")
        }

        let systemAudio: SelfTestOutcome = if !systemAudioRequested {
            .skipped("turned off")
        } else if hasStereoAudioTrack {
            .ok(nil)
        } else {
            .warning("nothing was captured")
        }

        let microphoneOutcome: SelfTestOutcome = switch microphone {
        case .notSelected:
            .skipped("not selected")
        case .unavailable(let name):
            .warning("\(name) isn't connected")
        case .expected(let name):
            if !hasMonoAudioTrack {
                .warning("\(name) recorded nothing")
            } else if microphonePeak < MicrophoneSilence.floor {
                // T4's words and T4's measured floor — one vocabulary for one condition.
                .warning("silent — check that it isn't muted")
            } else {
                .ok(name)
            }
        }

        return CaptureSelfTestResult(
            screen: screen, systemAudio: systemAudio, microphone: microphoneOutcome)
    }

    /// Records for `duration` into `directory`, reads the result, and deletes the file. The caller
    /// passes a scratch directory — never the user's output folder.
    ///
    /// Runs its own session, so an armed replay keeps its ring and any recording in progress is
    /// untouched (two concurrent streams is the arrangement G5 §6.4 proved).
    public static func run(
        configuration: CaptureConfiguration,
        microphone: MicrophoneExpectation,
        in directory: URL
    ) async -> CaptureSelfTestResult {
        let url = directory.appendingPathComponent("selftest-\(UUID().uuidString).mov")
        defer { removeQuietly(url) }

        let session: RecordingSession
        do {
            session = try RecordingSession(configuration: configuration, outputURL: url)
        } catch {
            return failure("Couldn't start a test recording.")
        }

        let peak = PeakWatch()
        let sampler = Task {
            while !Task.isCancelled {
                peak.observe(session.microphoneLevel?.takePeakLevel() ?? 0)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        let stopper = Task {
            try? await Task.sleep(for: .seconds(duration))
            await session.stop()
        }
        defer { sampler.cancel(); stopper.cancel() }

        await session.start()
        var finishedURL: URL?
        var failureMessage: String?
        for await event in session.events {
            switch event {
            case .finished(let url, _, _): finishedURL = url
            case .failed(let message): failureMessage = message
            default: break
            }
        }
        sampler.cancel()

        if let failureMessage { return failure(failureMessage) }
        guard let finishedURL else { return failure("The test recording produced no file.") }
        defer { removeQuietly(finishedURL) }

        let tracks = await inspect(finishedURL)
        return verdict(
            videoPixelSize: tracks.videoPixelSize,
            hasStereoAudioTrack: tracks.hasStereoAudioTrack,
            hasMonoAudioTrack: tracks.hasMonoAudioTrack,
            systemAudioRequested: configuration.capturesSystemAudio,
            microphone: microphone,
            microphonePeak: peak.value)
    }

    // MARK: - Reading the file

    struct TrackSummary: Equatable {
        var videoPixelSize: CGSize?
        var hasStereoAudioTrack = false
        var hasMonoAudioTrack = false
    }

    static func inspect(_ url: URL) async -> TrackSummary {
        var summary = TrackSummary()
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks) else { return summary }
        for track in tracks {
            switch track.mediaType {
            case .video:
                if let size = try? await track.load(.naturalSize) { summary.videoPixelSize = size }
            case .audio:
                guard let formats = try? await track.load(.formatDescriptions) else { continue }
                for format in formats {
                    guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
                    else { continue }
                    if asbd.mChannelsPerFrame >= 2 { summary.hasStereoAudioTrack = true }
                    if asbd.mChannelsPerFrame == 1 { summary.hasMonoAudioTrack = true }
                }
            default:
                break
            }
        }
        return summary
    }

    private static func failure(_ message: String) -> CaptureSelfTestResult {
        CaptureSelfTestResult(
            screen: .failed(message), systemAudio: .failed(message), microphone: .failed(message))
    }

    private static func removeQuietly(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: OutputLocation.partialURL(for: url))
    }
}

/// The loudest mic peak seen across the test. Written from the sampling task, read at the end.
private final class PeakWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    func observe(_ sample: Float) { lock.lock(); peak = max(peak, sample); lock.unlock() }
    var value: Float { lock.lock(); defer { lock.unlock() }; return peak }
}
