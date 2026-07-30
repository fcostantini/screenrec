import Foundation
import Testing

@testable import AppCore

@MainActor
@Suite struct LoginItemTests {

    /// Stands in for `SMAppService`: records calls and can be seeded/failed/approval-gated.
    final class FakeLoginItem: LoginItemManaging {
        var enabled: Bool
        var failNextSet = false
        /// A register() that lands in `.requiresApproval`: registered (isEnabled true) but pending.
        var approvalOnEnable = false
        private(set) var setCalls: [Bool] = []

        init(enabled: Bool = false) { self.enabled = enabled }

        private(set) var needsApproval = false
        var isEnabled: Bool { enabled }
        func setEnabled(_ value: Bool) throws {
            setCalls.append(value)
            if failNextSet { failNextSet = false; throw CocoaError(.xpcConnectionInterrupted) }
            enabled = value
            needsApproval = value && approvalOnEnable
        }
    }

    private func makeState(_ item: FakeLoginItem) -> AppState {
        let state = AppState(defaults: TestDefaults.make("login"))
        state.loginItem = item
        return state
    }

    @Test func syncSeedsFromTheServiceWithoutReRegistering() {
        let item = FakeLoginItem(enabled: true)
        let state = makeState(item)
        state.syncLaunchAtLogin()
        #expect(state.launchAtLogin)         // reflects the OS truth
        #expect(item.setCalls.isEmpty)       // seeding must not re-register
    }

    @Test func togglingWritesThroughToTheService() {
        let item = FakeLoginItem(enabled: false)
        let state = makeState(item)
        state.syncLaunchAtLogin()

        state.launchAtLogin = true
        #expect(item.setCalls == [true])
        #expect(item.isEnabled)

        state.launchAtLogin = false
        #expect(item.setCalls == [true, false])
        #expect(!item.isEnabled)
    }

    @Test func aFailedToggleRevertsToActualStatus() async {
        let item = FakeLoginItem(enabled: false)
        let state = makeState(item)
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.syncLaunchAtLogin()

        item.failNextSet = true
        state.launchAtLogin = true           // the service refuses
        await Task.yield()                   // the revert is deferred a runloop (SwiftUI observability)
        #expect(!state.launchAtLogin)        // reverted, not left lying
        #expect(!item.isEnabled)
        #expect(posted.contains { $0.title == "Couldn't change launch at login" })
    }

    @Test func requiresApprovalKeepsTheToggleOnAndPromptsTheUser() {
        // register() succeeds into .requiresApproval: the item is registered (isEnabled true),
        // so the toggle must stay on, and the user is told to approve it in System Settings.
        let item = FakeLoginItem(enabled: false)
        item.approvalOnEnable = true
        let state = makeState(item)
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.syncLaunchAtLogin()

        state.launchAtLogin = true
        #expect(state.launchAtLogin)         // stays on — the item IS registered
        #expect(posted.contains { $0.title == "Approve launch at login" })
    }
}
