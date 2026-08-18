import AppKit
import Testing

@testable import AppShell

/// Whether the app is in the Dock and ⌘-Tab (M37-T1, ADR-023). The rule is one line, and the defect
/// it replaces was that there was no rule: a minimized window had no route back.
@MainActor
@Suite struct WindowPolicyTests {

    @Test func withNoWindowOpenTheAppStaysOutOfTheDock() {
        #expect(WindowPolicy.activationPolicy(openWindows: 0) == .accessory)
    }

    @Test func anyOpenWindowEarnsTheDockAndCommandTab() {
        #expect(WindowPolicy.activationPolicy(openWindows: 1) == .regular)
        #expect(WindowPolicy.activationPolicy(openWindows: 3) == .regular)
    }
}
