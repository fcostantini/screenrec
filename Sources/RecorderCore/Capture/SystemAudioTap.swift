import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation

/// System audio as a Core Audio **process tap**, so one app can be silenced without its windows
/// leaving the frame (M27). SCK's audio is a content filter and cannot do that; a tap can, including
/// for an app with no window at all — the case `SCShareableContent` never lists (docs/02 §1a-ii).
///
/// Routed as `.systemAudio`, in SCK's own format, so no consumer knows the difference.
/// ⚠️ An ungranted tap returns `noErr` and a stream of **zeros** — never infer health from a status
/// code here (docs/07).
final class SystemAudioTap: @unchecked Sendable {
    enum TapError: Error, Equatable {
        case noDefaultOutputDevice
        case tapFailed(OSStatus)
        case deviceFailed(OSStatus)
        case startFailed(OSStatus)
    }

    private let router: SampleRouter
    /// A tap's rate follows the output device, so it is normalised to one format before the router
    /// sees it (M27-T5). Touched only from the IOProc — `convert` holds converter state and is not
    /// thread-safe, which is why the keep-alive below builds its silence already in the target.
    private let resampler = ResampledMicInput(target: ResampledMicInput.systemAudioTarget)
    /// Fires when the tap runs but carries nothing while something is playing (M27-T4).
    private let onSilent: @Sendable () -> Void
    private var watchdog: TapSilenceWatchdog?
    private var poll: DispatchSourceTimer?
    /// Emits silence when the tap has nothing to deliver, so the file's shape doesn't depend on
    /// whether anything happened to be playing (M27-T4).
    private var keepAlive: DispatchSourceTimer?
    private var lastDelivery: TimeInterval = 0
    private let lock = NSLock()
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format: CMAudioFormatDescription?

    init(router: SampleRouter, onSilent: @escaping @Sendable () -> Void = {}) {
        self.router = router
        self.onSilent = onSilent
    }

    /// Starts tapping everything except `silencedBundleIDs`.
    ///
    /// ⚠️ A bundle ID the audio system doesn't know **cannot be silenced** — it has no process
    /// object until it first plays — and the exclusion is then a no-op the caller must surface
    /// (measured, docs/07). `unsilenceable` names those, so nothing has to guess later.
    @discardableResult
    func start(silencing silencedBundleIDs: [String]) throws -> [String] {
        // Every object for each app, not the first: a browser or a music app runs several audio
        // helper processes under one bundle ID, and silencing one would leave the rest audible.
        let objects = AudioProcesses.objects(forBundleIDs: silencedBundleIDs)
        let excluded = silencedBundleIDs.flatMap { objects[$0] ?? [] }
        let unsilenceable = silencedBundleIDs.filter { objects[$0]?.isEmpty ?? true }

        guard let outputUID = Self.defaultOutputDeviceUID() else { throw TapError.noDefaultOutputDevice }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.name = "screenrec system audio"
        description.uuid = UUID()
        description.isPrivate = true  // not offered to other apps as an input device
        description.muteBehavior = .unmuted  // the user still hears what is being recorded

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr else { throw TapError.tapFailed(tapStatus) }

        guard let tapUID = Self.stringProperty(newTap, kAudioTapPropertyUID),
            let streamFormat = Self.tapFormat(newTap)
        else {
            AudioHardwareDestroyProcessTap(newTap)
            throw TapError.tapFailed(kAudioHardwareUnspecifiedError)
        }

        // Private, so it never appears in Sound settings; drift-compensated against the output it
        // shadows.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "screenrec system audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID,
            ]],
        ]
        var newDevice = AudioObjectID(kAudioObjectUnknown)
        let deviceStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newDevice)
        guard deviceStatus == noErr else {
            AudioHardwareDestroyProcessTap(newTap)
            throw TapError.deviceFailed(deviceStatus)
        }

        lock.lock()
        tap = newTap
        device = newDevice
        format = streamFormat
        lock.unlock()

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newDevice, nil) {
            [weak self] _, inputData, inputTime, _, _ in
            self?.emit(inputData, at: inputTime)
        }
        guard procStatus == noErr, let newProcID else {
            stop()
            throw TapError.startFailed(procStatus)
        }
        let startStatus = AudioDeviceStart(newDevice, newProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newDevice, newProcID)
            stop()
            throw TapError.startFailed(startStatus)
        }
        // A tap that has lost permission is indistinguishable from a quiet Mac by status code
        // alone (docs/07), so the check is level plus a cross-check — see `TapSilenceWatchdog`.
        let watchdog = TapSilenceWatchdog(
            isAnythingPlaying: { AudioProcesses.isAnythingPlaying() }, onSilent: onSilent)
        let timer = DispatchSource.makeTimerSource(queue: Self.pollQueue)
        timer.schedule(
            deadline: .now() + TapSilenceWatchdog.checkInterval,
            repeating: TapSilenceWatchdog.checkInterval)
        timer.setEventHandler { watchdog.check() }
        timer.resume()

        // SCK's audio delivers buffers continuously, silence included; a tap only fires when a
        // process is producing output. Without this, a take recorded on a quiet Mac has **no audio
        // track at all** while the same take with music has one — a file whose shape depends on
        // luck. So the gap is filled rather than left (Franco's ruling, 2026-08-03).
        let silence = DispatchSource.makeTimerSource(queue: Self.pollQueue)
        silence.schedule(deadline: .now() + Self.keepAliveInterval, repeating: Self.keepAliveInterval)
        silence.setEventHandler { [weak self] in self?.emitSilenceIfIdle() }
        silence.resume()

        lock.lock()
        procID = newProcID
        self.watchdog = watchdog
        poll = timer
        keepAlive = silence
        lastDelivery = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        return unsilenceable
    }

    func stop() {
        lock.lock()
        poll?.cancel()
        poll = nil
        keepAlive?.cancel()
        keepAlive = nil
        watchdog = nil
        let (currentDevice, currentProc, currentTap) = (device, procID, tap)
        device = AudioObjectID(kAudioObjectUnknown)
        procID = nil
        tap = AudioObjectID(kAudioObjectUnknown)
        format = nil
        lock.unlock()

        if let currentProc, currentDevice != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(currentDevice, currentProc)
            AudioDeviceDestroyIOProcID(currentDevice, currentProc)
        }
        if currentDevice != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(currentDevice)
        }
        if currentTap != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(currentTap)
        }
    }

    /// One IOProc buffer, as the router's `.systemAudio`. On the device's real-time thread: it takes
    /// the lock only to read the format, and does no work that can block.
    private func emit(
        _ inputData: UnsafePointer<AudioBufferList>, at inputTime: UnsafePointer<AudioTimeStamp>
    ) {
        lock.lock()
        let currentFormat = format
        let currentWatchdog = watchdog
        lock.unlock()
        guard let currentFormat,
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(currentFormat)?.pointee
        else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, let data = first.mData, first.mDataByteSize > 0 else { return }
        let byteLength = Int(first.mDataByteSize)
        let frames = asbd.mBytesPerFrame > 0 ? byteLength / Int(asbd.mBytesPerFrame) : 0
        guard frames > 0 else { return }

        // The host clock, which is what SCK's own buffers are stamped on — so `TimestampRebaser`
        // sees one timeline and needs no special case (02 §5).
        let stamp = inputTime.pointee
        let pts = (stamp.mFlags.contains(.hostTimeValid))
            ? CMClockMakeHostTimeFromSystemUnits(stamp.mHostTime)
            : CMClockGetTime(CMClockGetHostTimeClock())

        guard let sample = PCMSampleBuffer.make(
            format: currentFormat, sampleCount: frames, pts: pts, byteLength: byteLength,
            fill: { destination in
                destination.copyMemory(from: data, byteCount: byteLength)
                return true
            })
        else { return }
        guard let normalized = resampler.convert(sample) else { return }
        lock.lock()
        lastDelivery = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        // Every 16th sample: enough to see whether anything is there at all, and this is a
        // real-time thread.
        if let currentWatchdog {
            let floats = data.assumingMemoryBound(to: Float.self)
            var peak: Float = 0
            for index in stride(from: 0, to: byteLength / MemoryLayout<Float>.size, by: 16) {
                peak = max(peak, abs(floats[index]))
            }
            currentWatchdog.note(peak: peak)
        }
        router.route(normalized, type: .systemAudio)
    }

    /// One keep-alive buffer's worth. Short enough that a resuming tap interleaves cleanly —
    /// `TimestampRebaser` keeps each track's PTS strictly monotonic, so a late real buffer is
    /// handled rather than corrupting the writer.
    private static let keepAliveInterval: TimeInterval = 0.2

    /// A buffer of silence when the tap has delivered nothing since the last tick.
    private func emitSilenceIfIdle() {
        lock.lock()
        let idle = ProcessInfo.processInfo.systemUptime - lastDelivery >= Self.keepAliveInterval
        let currentFormat = format
        if idle { lastDelivery = ProcessInfo.processInfo.systemUptime }
        lock.unlock()
        guard idle, currentFormat != nil else { return }
        let target = ResampledMicInput.systemAudioTarget
        let asbd = target.streamDescription.pointee
        let frames = Int(asbd.mSampleRate * Self.keepAliveInterval)
        let byteLength = frames * Int(asbd.mBytesPerFrame)
        guard let sample = PCMSampleBuffer.make(
            format: target.formatDescription, sampleCount: frames,
            pts: CMClockGetTime(CMClockGetHostTimeClock()), byteLength: byteLength,
            fill: { destination in
                memset(destination, 0, byteLength)
                return true
            })
        else { return }
        router.route(sample, type: .systemAudio)
    }

    private static let pollQueue = DispatchQueue(label: "dev.fcostantini.screenrec.tapwatch")

    // MARK: - Core Audio lookups

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return nil }
        return stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
    }

    private static func tapFormat(_ tap: AudioObjectID) -> CMAudioFormatDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd) == noErr else {
            return nil
        }
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr
        else { return nil }
        return format
    }

    private static func stringProperty(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // `Unmanaged`, not `CFString?`: a raw pointer to a variable holding an object reference is
        // what the compiler warns about, and these getters hand back a +1 string.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
            let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}
