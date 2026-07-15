import Foundation

/// Runs `tick` every `interval` until the returned task is cancelled.
///
/// Three monitors now need exactly this loop (mic-loss, disk floor, capture stall), and each
/// hand-rolled copy had to re-learn the same two lessons the hard way:
/// - **Cancellation must exit the loop**, not be swallowed by `try?` — otherwise one more tick
///   runs after teardown, racing whatever the owner did next.
/// - **The caller must keep the handle.** Dropping a `Task` reference does not cancel it; the
///   loop then wakes forever and keeps its captures alive.
///
/// - ⚠️ **`tick` must not capture the owning actor.** Nonisolated access to an actor's `Sendable`
///   `let` compiles cleanly, so `pollingTask { self.watchdog.check() }` looks fine and creates
///   owner → task → closure → owner: `deinit` never runs, so the cancel in `deinit` never fires
///   and the loop wakes forever holding the owner alive — the second bullet's leak, reached
///   through the door it doesn't mention. Bind the monitor to a local first. (The same hazard
///   reaches a monitor's *own* callbacks, not just this one: a `@Sendable` handler capturing the
///   owner closes the identical cycle through whatever retains the monitor.)
/// - ⚠️ **Disarm before teardown if the tick publishes anything.** Stopping a capture suspends
///   for seconds (Bluetooth teardown) while the owner still looks alive, and buffer delivery has
///   already ceased — so a monitor polling across that window reports on a recording that is
///   perfectly complete. The rule: a tick that *publishes* (an event, a log line) must be
///   cancelled before the owner starts tearing down; a tick that merely *requests an idempotent
///   action* survives it, but relies on that idempotence and is one refactor from not.
///
/// Deliberately a free (nonisolated) function: `Task {}` written inside an actor's method would
/// *inherit* that actor's isolation, and every caller's `tick` is a lock-guarded `Sendable`
/// monitor with no business occupying an actor to do one comparison. ⚠️ The flip side is that
/// ticks now run genuinely concurrently with the owner's own actor-isolated work, so a `tick`
/// that publishes anything must tolerate racing whatever the owner is doing (the engine disarms
/// its watchdogs before teardown for exactly this reason).
func pollingTask(
    every interval: TimeInterval,
    _ tick: @escaping @Sendable () -> Void
) -> Task<Void, Never> {
    Task {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            tick()
        }
    }
}
