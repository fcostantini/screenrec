import Foundation

/// The launch-time rules, kept out of `AppDelegate` so they can be answered without one: building
/// an `AppDelegate` installs a status item and can start capture.
enum LaunchPolicy {

    /// The argument `Relaunch.now()` passes to the copy it spawns.
    static let relaunchArgument = "--relaunching"

    /// Whether this copy should hand over to one that is already running.
    ///
    /// ⚠️ `Relaunch.now()` spawns a second copy **deliberately** (`open -n`) and terminates the first
    /// only afterwards, so the two overlap by design. A relaunching copy therefore never yields —
    /// otherwise granting Screen Recording would leave the user with no app at all.
    static func yieldsToRunningInstance(arguments: [String], otherInstances: Int) -> Bool {
        guard !arguments.contains(relaunchArgument) else { return false }
        return otherInstances > 0
    }

}
