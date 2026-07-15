/// What the menu-bar status item shows (docs/06 "Status item").
///
/// The icon is the whole of the app's UI while the menu is closed, so it is the one piece of
/// state that must never lie about what the capture is doing. Rendering — symbols, colours,
/// the recording pulse — belongs to the app target; this is only the state the drawing is a
/// function of, which is what lets the event mapping be tested without a UI host.
///
/// docs/06 lists a fourth state, replay-armed, as an idle icon with a dot badge. It arrives
/// with the menu toggle that can set it (M4-T2); nothing can arm replay yet.
public enum StatusIcon: Sendable, Equatable {
    /// Not recording: outline record circle, template-rendered so the menu bar tints it.
    case idle
    /// Filled red circle, subtly pulsing (static under Reduce Motion).
    case recording
    /// Half-filled amber circle: the capture runs on, but the output timeline is frozen.
    case paused
}
