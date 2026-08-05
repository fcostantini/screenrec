import Foundation
import Testing

@testable import AppShell

/// The launch-time rules (M30-T5/T6). Both are pure so they can be asserted without launching an
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

    // MARK: - The grant poll backs off (M30-T6)

    /// G4 §5.1 measured grant → relaunch as immediate; the first minutes must stay that way.
    @Test func theCheckStaysFastWhileTheUserIsPlausiblyGranting() {
        #expect(LaunchPolicy.grantPollInterval(sinceLaunch: .zero) == .seconds(1))
        #expect(LaunchPolicy.grantPollInterval(sinceLaunch: .seconds(119)) == .seconds(1))
    }

    /// An app left ungranted otherwise queries TCC once a second for as long as it runs.
    @Test func theCheckSlowsOnceTheGrantFlowHasPlainlyBeenAbandoned() {
        #expect(LaunchPolicy.grantPollInterval(sinceLaunch: .seconds(120)) == .seconds(5))
        #expect(LaunchPolicy.grantPollInterval(sinceLaunch: .seconds(3600)) == .seconds(5))
    }
}
