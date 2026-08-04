import AppCore

/// The status item's timing rules, kept out of the controller so they can be answered without one:
/// building a `StatusItemController` puts a real item in the menu bar, which a test must not do.
enum StatusItemPolicy {

    /// One registration at a time. `withObservationTracking` is one-shot and only re-arms while the
    /// menu is open, so without this every open leaves another armed that outlives it.
    static func registersObservation(menuIsOpen: Bool, alreadyObserving: Bool) -> Bool {
        menuIsOpen && !alreadyObserving
    }

    /// Only a recording breathes, and Reduce Motion means it doesn't.
    static func pulses(icon: StatusIcon, reduceMotion: Bool) -> Bool {
        icon == .recording && !reduceMotion
    }

    /// A still icon has nothing to advance, and while the pulse runs it already redraws faster than
    /// this tick.
    static func redrawsOnClockTick(isPulsing: Bool, hasClock: Bool) -> Bool {
        !isPulsing && hasClock
    }
}
