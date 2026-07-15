import Foundation
import Observation
import RecorderCore

/// The menu-bar app's view state.
///
/// It consumes `EngineEvent` — RecorderCore's single event surface (docs/01), the same stream
/// the CLI's `record` reads — and exposes what the UI draws. The app adds no capture behaviour
/// of its own (docs/06); every state here is something a recording session told us.
///
/// MainActor-isolated because every reader is a view. Nothing on the sample path touches this:
/// events arrive already hopped off the capture queues by `RecordingSession`.
@MainActor
@Observable
public final class AppState {

    /// What the status item shows right now.
    public private(set) var statusIcon: StatusIcon = .idle

    public init() {}

    /// Drives the state off a `RecordingSession.events` stream until the session finishes.
    /// The stream terminates after `finished`/`failed`, which returns the icon to `.idle`.
    public func consume(_ events: AsyncStream<EngineEvent>) async {
        for await event in events { apply(event) }
    }

    /// Folds one engine event into the state. Internal: the app drives this through
    /// `consume(_:)` and has no reason to hand-feed events.
    func apply(_ event: EngineEvent) {
        switch event {
        case .started, .resumed:
            statusIcon = .recording
        case .paused:
            statusIcon = .paused
        case .stopped, .finished, .failed:
            // Every ending is the same to the icon — including the fail-stops, which are
            // ADR-007 successes with a cause. The cause reaches the user as a notification
            // (M4-T5); a distinct icon for it would be alarm with nothing to act on.
            statusIcon = .idle
        case .microphoneLost:
            // The one mid-recording problem that does not end the session (ADR-012): the mic
            // track ends, the recording continues, and so the icon must keep saying so.
            break
        case .fileProgress:
            break   // elapsed and size are the menu header's business (M4-T2)
        }
    }
}
