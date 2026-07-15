/// What the menu-bar status item shows (docs/06 "Status item").
///
/// State only; rendering belongs to the app target, which keeps the event mapping testable
/// without a UI host. docs/06's fourth state, replay-armed, waits on M5 — nothing can arm
/// replay until then.
public enum StatusIcon: Sendable, Equatable {
    /// Not recording: outline record circle, template-rendered so the menu bar tints it.
    case idle
    /// Filled red circle, subtly pulsing (static under Reduce Motion).
    case recording
    /// Half-filled amber circle: the capture runs on, but the output timeline is frozen.
    case paused
}
