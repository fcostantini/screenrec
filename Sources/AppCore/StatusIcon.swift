/// What the menu-bar status item shows (docs/06 "Status item").
///
/// The icon is the whole of the app's UI while the menu is closed, so it is the one piece of
/// state that must never lie about what the capture is doing. Rendering — symbols, colours,
/// the recording pulse — belongs to the app target; this is only the state the drawing is a
/// function of, which is what lets the event mapping be tested without a UI host.
///
/// docs/06 lists a fourth state, replay-armed, as an idle icon with a dot badge. It arrives
/// with M4-T4, which owns the `replayArmed` setting that persists it — nothing can arm replay
/// until M5 reads that key, so a badge before then would report a state no one can be in.
public enum StatusIcon: Sendable, Equatable {
    /// Not recording: outline record circle, template-rendered so the menu bar tints it.
    case idle
    /// Filled red circle, subtly pulsing (static under Reduce Motion).
    case recording
    /// Half-filled amber circle: the capture runs on, but the output timeline is frozen.
    case paused
}
