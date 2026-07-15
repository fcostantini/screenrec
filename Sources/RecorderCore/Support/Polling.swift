import Foundation

/// Runs `tick` every `interval` until the returned task is cancelled.
///
/// - **The caller must keep the handle.** Dropping a `Task` reference does not cancel it; the
///   loop then wakes forever and keeps its captures alive.
/// - ⚠️ **`tick` must not capture the owning actor.** Nonisolated access to an actor's `Sendable`
///   `let` compiles cleanly, so `pollingTask { self.watchdog.check() }` closes
///   owner → task → closure → owner and `deinit` never runs. Bind the monitor to a local first;
///   the same hazard applies to a monitor's own `@Sendable` callbacks.
/// - ⚠️ **Disarm before teardown if the tick publishes anything.** Stopping a capture suspends
///   for seconds while the owner still looks alive, so a tick landing there reports on an
///   already-complete recording. A tick that only requests an idempotent action can survive it.
///
/// Free (nonisolated) on purpose: `Task {}` inside an actor's method would inherit that actor's
/// isolation. ⚠️ The flip side is that ticks run concurrently with the owner's isolated work.
func pollingTask(
    every interval: TimeInterval,
    _ tick: @escaping @Sendable () -> Void
) -> Task<Void, Never> {
    Task {
        while !Task.isCancelled {
            // Not `try?`: cancellation must exit the loop, or one more tick runs after teardown.
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            tick()
        }
    }
}
