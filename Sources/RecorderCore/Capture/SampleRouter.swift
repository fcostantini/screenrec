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

/// Fans one capture stream out to many consumers, so recording and instant replay (and
/// the started-detector) can all tap the same `SCStream`. Thread-safe: attach/detach and
/// the fan-out snapshot are lock-guarded.
public final class SampleRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var consumers: [ObjectIdentifier: any SampleConsumer] = [:]

    public init() {}

    /// Retains the consumer strongly until `detach` — callers must detach when done
    /// (e.g. MovieRecorder on stop) or the consumer leaks.
    public func attach(_ consumer: any SampleConsumer) {
        lock.lock()
        consumers[ObjectIdentifier(consumer)] = consumer
        lock.unlock()
    }

    public func detach(_ consumer: any SampleConsumer) {
        lock.lock()
        consumers[ObjectIdentifier(consumer)] = nil
        lock.unlock()
    }

    /// Deliver a captured buffer to every attached consumer. Called on SCK's serial
    /// sample-handler queues. Incomplete video frames (screen-unchanged ticks) are dropped
    /// here so consumers only ever see real frames (docs/02 §1). The consumer list is
    /// snapshotted under the lock and delivered outside it — a slow consumer can't block
    /// attach/detach or hold the capture queue beyond its own work.
    func route(_ buffer: CMSampleBuffer, type: SourceType) {
        if type == .screen, !Self.isCompleteVideoFrame(buffer) { return }
        lock.lock()
        let snapshot = Array(consumers.values)
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
