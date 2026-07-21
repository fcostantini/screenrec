import Foundation

/// The recording's elapsed-time basis for the live menu-bar clock (M9-T3). Pause-correct: it
/// counts *recorded* time, so a paused span doesn't advance it.
///
/// Deliberately changes only on start/pause/resume — never per second — so the label computes the
/// ticking value locally (`elapsed(now:)`) and no per-second publish churns the open menu (M6-T10).
public struct RecordingClock: Equatable, Sendable {
    /// Recorded time banked before the current running span (i.e. the total across prior spans).
    public var accumulated: TimeInterval
    /// When the current running span began; nil while paused, so the value is frozen.
    public var runningSince: Date?

    public init(accumulated: TimeInterval, runningSince: Date?) {
        self.accumulated = accumulated
        self.runningSince = runningSince
    }

    /// Recorded time as of `now` — injected, so the computation is testable without wall-clock.
    public func elapsed(now: Date) -> TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Bank the running span into `accumulated` and freeze (pause).
    public mutating func bankAndFreeze(now: Date) {
        accumulated = elapsed(now: now)
        runningSince = nil
    }
}
