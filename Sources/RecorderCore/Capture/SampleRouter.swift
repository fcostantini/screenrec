import CoreMedia
import ScreenCaptureKit

/// Which capture source a sample buffer came from.
public enum SourceType: Sendable, Equatable {
    case screen
    case systemAudio
    case microphone
}

/// A sink for captured sample buffers. Implementations receive on SCK's serial capture
/// queues (background threads), so `consume` must be light and internally thread-safe.
public protocol SampleConsumer: AnyObject, Sendable {
    func consume(_ buffer: CMSampleBuffer, type: SourceType)
}

/// Fans one capture stream out to many consumers, so recording and instant replay can tap
/// the same `SCStream`. Thread-safe: attach/detach and the fan-out snapshot are lock-guarded.
public final class SampleRouter: @unchecked Sendable {
    private let lock = NSLock()
    /// Identity-keyed source of truth, for dedup-on-attach and detach.
    private var consumers: [ObjectIdentifier: any SampleConsumer] = [:]
    /// A pre-built snapshot of `consumers.values`, rebuilt only on attach/detach (rare) so `route`
    /// never allocates on the per-buffer hot path (docs/01: sample-path handlers stay
    /// allocation-light). Mutated only under `lock`, and always *replaced* — never mutated in place
    /// — so a `route` snapshot taken under the lock stays a stable, immutable view after unlock.
    private var consumerList: [any SampleConsumer] = []

    public init() {}

    /// Retains the consumer strongly until `detach` — callers must detach when done
    /// (e.g. MovieRecorder on stop) or the consumer leaks.
    public func attach(_ consumer: any SampleConsumer) {
        lock.lock()
        consumers[ObjectIdentifier(consumer)] = consumer
        consumerList = Array(consumers.values)
        lock.unlock()
    }

    /// Not a hard callback barrier: `route` reads the consumer snapshot under the lock and delivers
    /// outside it, so a route already in flight can still deliver **one late `consume`** to a consumer
    /// detached a moment ago. Safe today — consumers tolerate a trailing buffer — but it's a real
    /// contract: detaching does not guarantee no further `consume` (M14-T3).
    public func detach(_ consumer: any SampleConsumer) {
        lock.lock()
        consumers[ObjectIdentifier(consumer)] = nil
        consumerList = Array(consumers.values)
        lock.unlock()
    }

    /// Deliver a captured buffer to every attached consumer. Called on SCK's serial
    /// sample-handler queues. Incomplete video frames are dropped here so consumers only see
    /// real frames (docs/02 §1). Reads the pre-built consumer snapshot's reference under the lock
    /// and delivers outside it — no per-buffer allocation, and a slow consumer can't block
    /// attach/detach.
    func route(_ buffer: CMSampleBuffer, type: SourceType) {
        if type == .screen, !Self.isCompleteVideoFrame(buffer) { return }
        lock.lock()
        let snapshot = consumerList
        lock.unlock()
        for consumer in snapshot {
            consumer.consume(buffer, type: type)
        }
    }

    /// SCK marks a frame `.complete` when it carries real pixels; `.idle`/incomplete
    /// frames are screen-unchanged ticks that must not reach consumers (docs/02 §1).
    static func isCompleteVideoFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue) else {
            return false
        }
        return status == .complete
    }
}
