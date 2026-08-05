import AVFoundation
import Foundation

/// The AVAssetWriter drain skeleton shared by `ReplayMuxer` and `Exporter` (M14-T2, was "the
/// ReplayMuxer idiom" hand-rolled in both). `requestMediaDataWhenReady` re-invokes the block as the
/// writer drains; `pump` produces + appends the next sample and returns `true` to continue or
/// `false` to finish — a clean end (no more samples / the reader or writer left `.writing`) or a
/// failure it has already reported to a `FirstError`.
enum WriterDrain {

    /// Pumps one writer input on `queue`. The `done` flag guards the single `group.leave()` against a
    /// re-fire after finishing: a failed writer may never call the block again, so leaving exactly
    /// once is what keeps `group.wait()` from deadlocking (and the replay `isSaving` latch from
    /// wedging every later save). The caller balances `enter` with the one `leave` here.
    static func drain(
        into input: AVAssetWriterInput,
        on queue: DispatchQueue,
        group: DispatchGroup,
        pump: @escaping () -> Bool
    ) {
        group.enter()
        // Confined to `queue`: `requestMediaDataWhenReady` re-invokes its block only there, so all
        // three are single-threaded in fact — a guarantee the compiler cannot see across the
        // AVFoundation boundary. Stated here rather than hidden behind a file-wide
        // `@preconcurrency import`, which would silence the next one too.
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let pump = pump
        nonisolated(unsafe) var done = false
        input.requestMediaDataWhenReady(on: queue) {
            guard !done else { return }
            while input.isReadyForMoreMediaData {
                guard pump() else {
                    done = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }
}

/// The first append/write problem across a set of drains; one message is enough to fail the whole
/// mux or export (M14-T2). `@unchecked Sendable`: the lock makes the shared access safe.
final class FirstError: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var message: String? { lock.withLock { stored } }

    /// Keeps the first message; later ones are the fallout of the first.
    func report(_ message: String) { lock.withLock { if stored == nil { stored = message } } }
}
