import CoreMedia
import Foundation

/// The measured thresholds behind `.microphoneSilent`. Public because the notice copy quotes the
/// duration, and a number in two places drifts.
public enum MicrophoneSilence {
    /// A muted device delivers exact digital zeros; a live quiet room measured −79 … −43 dBFS
    /// depending on the microphone (docs/07), so this sits ~11 dB below the quietest real audio.
    public static let floorDBFS: Float = -90
    /// The floor as a linear peak amplitude — what a sample is actually compared against.
    public static let floor = pow(Float(10), floorDBFS / 20)
    /// How long the quiet must last before it is worth saying. Ten seconds of a lost take is cheap;
    /// a notice that fires on a pause in speech is not (late-and-right, docs/03 M16-T4). It also
    /// absorbs the ~1 s of digital zeros SCK delivers while a Bluetooth route spins up.
    public static let duration: TimeInterval = 10
}

/// Read-only access to the live microphone level, for a UI meter (M16-T5). Deliberately a *pull*:
/// a per-buffer push would put ~40 publishes a second into the observation graph, which M6-T10
/// forbids anywhere near the menu.
public protocol MicrophoneLevelSource: AnyObject, Sendable {
    /// Loudest sample since the last call, then resets — poll it at the meter's frame rate and
    /// this is exactly "the peak over the last frame". 0 when nothing arrived.
    func takePeakLevel() -> Float
}

/// Detects a microphone that is connected and delivering buffers which contain nothing — muted at
/// the switch, gain at zero, or an input with nothing on it. `MicrophoneWatchdog`'s sibling: that
/// one asks whether buffers arrive, this one whether they carry anything. Firing is a notice, never
/// a termination: the recording continues (ADR-012).
///
/// Thresholds are measured, not guessed (docs/07): a muted device delivers exact digital zeros,
/// while a live quiet room reads −79 … −43 dBFS depending on the mic. The run length matters as
/// much as the floor — SCK opens a Bluetooth route with ~1 s of zeros, so the decision is never
/// "this buffer is quiet".
///
/// `consume` runs on the mic capture queue: state is lock-guarded (docs/01) and handlers fire
/// outside the lock.
final class MicrophoneSilenceWatchdog: SampleConsumer, MicrophoneLevelSource, @unchecked Sendable {
    /// Suggested `check()` cadence; notice latency is bounded by the run length + this.
    static let checkInterval: TimeInterval = 1

    private let duration: TimeInterval
    private let now: @Sendable () -> TimeInterval

    private let lock = NSLock()
    private let onSilent: @Sendable () -> Void
    private let onAudible: @Sendable () -> Void
    /// When the current unbroken run of sub-floor buffers began; nil once anything audible lands.
    private var quietSince: TimeInterval?
    private var hasReportedSilence = false
    /// Loudest sample since the meter last read; the same scan that feeds the silence decision, so
    /// the level costs no second pass over the samples.
    private var peakSinceRead: Float = 0

    /// `systemUptime` is monotonic and does not advance during system sleep, so a machine that
    /// slept mid-recording doesn't wake and call the mic silent for the nap.
    init(
        duration: TimeInterval = MicrophoneSilence.duration,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onSilent: @escaping @Sendable () -> Void,
        onAudible: @escaping @Sendable () -> Void
    ) {
        self.duration = duration
        self.now = now
        self.onSilent = onSilent
        self.onAudible = onAudible
    }

    /// Runs on the mic capture queue. The type filter is load-bearing: system audio is silent all
    /// the time by design, and saying so would train the user to ignore the notice.
    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .microphone, let peak = Self.peakAmplitude(of: buffer) else { return }
        lock.lock()
        var announceAudible = false
        peakSinceRead = max(peakSinceRead, peak)
        if peak >= MicrophoneSilence.floor {
            quietSince = nil
            if hasReportedSilence {
                hasReportedSilence = false
                announceAudible = true
            }
        } else if quietSince == nil {
            quietSince = now()
        }
        lock.unlock()
        if announceAudible { onAudible() }   // outside the lock — it is non-reentrant
    }

    func takePeakLevel() -> Float {
        lock.lock()
        defer { peakSinceRead = 0; lock.unlock() }
        return peakSinceRead
    }

    /// Fire `onSilent` once per run of quiet. Silent until the run passes `duration`, so the
    /// route-spin-up zeros and any pause in speech pass unremarked.
    func check() {
        lock.lock()
        var fire = false
        if !hasReportedSilence, let since = quietSince, now() - since >= duration {
            hasReportedSilence = true
            fire = true
        }
        lock.unlock()
        if fire { onSilent() }
    }

    /// Loudest sample in a buffer, or nil if it carries no readable Float32 audio. Mic buffers
    /// reach consumers normalized to 48 kHz mono Float32 (`ResampledMicInput`), so this never sees
    /// a device format. Peak, not RMS: an average would wash out a single real sound.
    static func peakAmplitude(of buffer: CMSampleBuffer) -> Float? {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32
        else { return nil }

        var peak: Float = 0
        let read: ()? = try? buffer.withAudioBufferList { list, _ in
            for audioBuffer in list {
                guard let data = audioBuffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<(Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size) {
                    peak = max(peak, abs(samples[index]))
                }
            }
        }
        return read == nil ? nil : peak
    }
}
