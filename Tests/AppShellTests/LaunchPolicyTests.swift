import Foundation
import Testing

@testable import AppShell

/// The single-instance rule (M30-T5). Pure so they can be asserted without launching an
/// app — building an `AppDelegate` installs a status item and can start capture.
@Suite struct LaunchPolicyTests {

    // MARK: - Handing over to a copy already running (M30-T5)

    @Test func aFirstCopyKeepsRunning() {
        #expect(!LaunchPolicy.yieldsToRunningInstance(arguments: [], otherInstances: 0))
    }

    @Test func aSecondCopyHandsOver() {
        #expect(LaunchPolicy.yieldsToRunningInstance(arguments: [], otherInstances: 1))
    }

    /// The case that makes a naive guard worse than no guard. `Relaunch.now()` runs `open -n`, which
    /// spawns a second copy on purpose and terminates the first only afterwards — so the relaunching
    /// copy sees its own predecessor still alive. Yielding there would leave a first-run user with
    /// **no app at all** the moment they granted Screen Recording.
    @Test func aRelaunchingCopyNeverYieldsToTheOneItIsReplacing() {
        #expect(
            !LaunchPolicy.yieldsToRunningInstance(
                arguments: [LaunchPolicy.relaunchArgument], otherInstances: 1))
    }

    /// The flag has to survive alongside whatever else `open` passes.
    @Test func theRelaunchFlagIsFoundAmongOtherArguments() {
        #expect(
            !LaunchPolicy.yieldsToRunningInstance(
                arguments: ["-psn_0_123", LaunchPolicy.relaunchArgument], otherInstances: 2))
    }
}
