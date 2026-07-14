import CoreMedia
import Testing
@testable import RecorderCore

/// A minimal empty CMSampleBuffer (a valid object with no data/format). Enough to
/// exercise fan-out, which passes buffers opaquely. Routed as `.systemAudio` so the
/// router's video-completeness filter (which would drop this) doesn't apply.
private func makeMarkerBuffer() -> CMSampleBuffer {
    var buffer: CMSampleBuffer?
    let status = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: nil,
        sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
        sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer)
    precondition(status == noErr, "CMSampleBufferCreate failed: \(status)")
    return buffer!
}

private final class CountingConsumer: SampleConsumer, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        lock.lock(); _count += 1; lock.unlock()
    }
}

@Suite struct SampleRouterTests {

    @Test func fansOutToAllAttachedConsumers() {
        let router = SampleRouter()
        let a = CountingConsumer(), b = CountingConsumer()
        router.attach(a)
        router.attach(b)
        let buffer = makeMarkerBuffer()
        router.route(buffer, type: .systemAudio)
        router.route(buffer, type: .systemAudio)
        #expect(a.count == 2)
        #expect(b.count == 2)
    }

    @Test func detachStopsDelivery() {
        let router = SampleRouter()
        let a = CountingConsumer()
        router.attach(a)
        router.route(makeMarkerBuffer(), type: .systemAudio)
        router.detach(a)
        router.route(makeMarkerBuffer(), type: .systemAudio)
        #expect(a.count == 1)
    }

    @Test func attachingSameConsumerTwiceDeliversOnce() {
        let router = SampleRouter()
        let a = CountingConsumer()
        router.attach(a)
        router.attach(a)
        router.route(makeMarkerBuffer(), type: .systemAudio)
        #expect(a.count == 1)
    }

    /// Concurrent route/attach/detach — the payoff is running under
    /// `swift test --sanitize=thread`: no data race on the consumer set.
    @Test func concurrentRouteAttachDetachIsThreadSafe() async {
        let router = SampleRouter()
        let consumers = (0..<8).map { _ in CountingConsumer() }
        for consumer in consumers { router.attach(consumer) }
        let buffer = makeMarkerBuffer()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0..<2000 { router.route(buffer, type: .systemAudio) }
            }
            group.addTask {
                for consumer in consumers { router.detach(consumer) }
            }
            group.addTask {
                for _ in 0..<16 { router.attach(CountingConsumer()) }
            }
        }
        // Reaching here without a crash or a sanitizer report is the assertion.
    }
}
