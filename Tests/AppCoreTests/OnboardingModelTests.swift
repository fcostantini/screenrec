import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// docs/03 asks for "every permission-state combination" — so this is a truth table, not a
/// sample. That matters more here than anywhere else in the app: most of these states are ones
/// this machine can't be put into without a throwaway bundle and a human declining a prompt
/// (02 §2), so if the logic is wrong, nothing else will catch it.
@Suite struct OnboardingModelTests {

    private static let states: [PermissionState] = [.granted, .notDetermined, .denied]

    private func rows(
        screen: PermissionState = .granted,
        hasAskedForScreen: Bool = false,
        microphone: PermissionState = .granted,
        microphoneRequired: Bool = false,
        notifications: PermissionState = .granted
    ) -> [OnboardingRow] {
        OnboardingModel.rows(
            screen: screen, hasAskedForScreen: hasAskedForScreen,
            microphone: microphone, microphoneRequired: microphoneRequired,
            notifications: notifications)
    }

    private func row(_ kind: PermissionKind, _ all: [OnboardingRow]) -> OnboardingRow {
        // Invariant: `rows` returns exactly one row per kind, which the test below pins.
        all.first { $0.id == kind }!
    }

    // MARK: - Shape

    @Test func alwaysExactlyThreeRowsInSpecOrder() {
        // docs/06's order is the reading order of the checklist; a reshuffle would be a
        // regression nobody would think to look for.
        #expect(rows().map(\.id) == [.screenRecording, .microphone, .notifications])
    }

    @Test(arguments: states, states)
    func everyCombinationYieldsAWellFormedChecklist(
        screen: PermissionState, microphone: PermissionState
    ) {
        for notifications in Self.states {
            for asked in [true, false] {
                for required in [true, false] {
                    let all = rows(
                        screen: screen, hasAskedForScreen: asked, microphone: microphone,
                        microphoneRequired: required, notifications: notifications)
                    #expect(all.count == 3)
                    // A satisfied row must never still be asking for something, and an
                    // unsatisfied one must always offer a way forward — the dead `Grant…`
                    // button this task exists to prevent (02 §2) is exactly the second rule
                    // being broken.
                    for r in all {
                        if r.isSatisfied {
                            #expect(r.action == .none)
                            #expect(!r.blocksRecording)
                        } else {
                            #expect(r.action != .none)
                        }
                        #expect(!r.title.isEmpty)
                        #expect(!r.detail.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Screen recording (the row that has to guess)

    @Test func screenGrantedIsDoneAndBlocksNothing() {
        let r = row(.screenRecording, rows(screen: .granted))
        #expect(r.isSatisfied)
        #expect(r.action == .none)
        #expect(!r.blocksRecording)
    }

    @Test(arguments: [PermissionState.notDetermined, .denied])
    func screenOffersGrantBeforeAsking(state: PermissionState) {
        let r = row(.screenRecording, rows(screen: state, hasAskedForScreen: false))
        #expect(r.action == .request)
        #expect(r.blocksRecording)
        #expect(r.detail.contains("relaunch"))       // docs/06 promises this before it happens
    }

    @Test(arguments: [PermissionState.notDetermined, .denied])
    func screenSwitchesToSystemSettingsOnceAsked(state: PermissionState) {
        // THE point of this task. macOS prompts once, ever (02 §2) — so a second `Grant…` is a
        // dead button. It flips on *having asked*, not on being denied, because macOS reports
        // `.notDetermined` for both "never asked" and "declined": the two are indistinguishable,
        // and this row must be right in both.
        let r = row(.screenRecording, rows(screen: state, hasAskedForScreen: true))
        #expect(r.action == .openSettings(.screenRecording))
        #expect(r.blocksRecording)
    }

    @Test func askingChangesNothingOnceGranted() {
        let r = row(.screenRecording, rows(screen: .granted, hasAskedForScreen: true))
        #expect(r.isSatisfied)
        #expect(r.action == .none)
    }

    // MARK: - Microphone (the row that never has to guess)

    @Test func microphoneNotDeterminedAsks() {
        let r = row(.microphone, rows(microphone: .notDetermined))
        #expect(r.action == .request)
    }

    @Test(arguments: [PermissionState.notDetermined, .denied])
    func anUnsatisfiedMicrophoneStopsCallingItselfOptionalOnceItIsBlocking(state: PermissionState) {
        // The copy has to follow the gate. Saying "only needed if you record a microphone" while
        // Start is greyed out *because of this row* tells the one person who is blocked by it
        // that it isn't their problem.
        let optional = row(.microphone, rows(microphone: state, microphoneRequired: false))
        let blocking = row(.microphone, rows(microphone: state, microphoneRequired: true))
        #expect(!blocking.blocksRecording == false)
        #expect(optional.detail != blocking.detail)
        #expect(!blocking.detail.localizedCaseInsensitiveContains("only needed"))
    }

    @Test func microphoneDeniedGoesStraightToSettings() {
        // Unlike screen, `authorizationStatus` reports a real `.denied` (02 §2) — no empiricism,
        // no asking first. And the route works: the decline is what created the row in System
        // Settings, which is why that pane needs no "+" (measured, M4-T3 spike).
        let r = row(.microphone, rows(microphone: .denied))
        #expect(r.action == .openSettings(.microphone))
        #expect(r.detail.contains("No restart needed."))
    }

    @Test(arguments: [PermissionState.notDetermined, .denied])
    func microphoneOnlyBlocksWhenOneIsSelected(state: PermissionState) {
        // docs/06 gates recording on rows 1–2, then says the mic is optional if the user picked
        // None. So an ungranted mic must not block someone recording their screen in silence.
        #expect(!row(.microphone, rows(microphone: state, microphoneRequired: false)).blocksRecording)
        #expect(row(.microphone, rows(microphone: state, microphoneRequired: true)).blocksRecording)
    }

    @Test func aGrantedMicrophoneNeverBlocksEvenWhenRequired() {
        #expect(!row(.microphone, rows(microphone: .granted, microphoneRequired: true)).blocksRecording)
    }

    // MARK: - Notifications (never blocks)

    @Test(arguments: states)
    func notificationsNeverBlockAnything(state: PermissionState) {
        // docs/06: optional, never gates. The app is fully functional without them.
        #expect(!row(.notifications, rows(notifications: state)).blocksRecording)
    }

    @Test func notificationsDeniedReadsAsSkippedNotBroken() {
        let r = row(.notifications, rows(notifications: .denied))
        #expect(r.detail.contains("Skipped"))
        #expect(r.action == .openSettings(.notifications))
    }

    // MARK: - Copy rules (docs/06)

    @Test func neverBlamesTheUserAndNeverNamesAnAPI() {
        // "Blocking problems name the fix, not the API" — and never as an accusation: the user
        // often clicked the wrong button once, months ago, and has no idea that's why.
        for screen in Self.states {
            for asked in [true, false] {
                for microphone in Self.states {
                    for notifications in Self.states {
                        let all = rows(
                            screen: screen, hasAskedForScreen: asked, microphone: microphone,
                            microphoneRequired: true, notifications: notifications)
                        for r in all {
                            let text = "\(r.title) \(r.detail)"
                            for word in ["TCC", "-3801", "error", "failed", "you denied", "invalid"] {
                                #expect(!text.localizedCaseInsensitiveContains(word),
                                        "row \(r.id) says \"\(word)\": \(text)")
                            }
                        }
                    }
                }
            }
        }
    }
}
