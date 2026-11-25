import AppKit
import Testing

@testable import AppShell

/// Windows the app counts as open without having built them (M42-T1, ADR-023).
@MainActor
@Suite struct GuestWindowsTests {

    /// Never ordered in, so nothing reaches the screen. Not released on close: ARC owns it.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func aWindowIsCountedOnceHoweverOftenItIsShown() {
        let guests = GuestWindows {}
        let panel = makeWindow()
        guests.add(panel)
        guests.add(panel)
        #expect(guests.count == 1)
    }

    @Test func closingItStopsTheCountAndSaysSo() {
        var closes = 0
        let guests = GuestWindows { closes += 1 }
        let panel = makeWindow()
        guests.add(panel)

        panel.close()

        #expect(guests.count == 0)
        #expect(closes == 1)
    }

    /// The panel is one shared window: the next preview shows the one that just closed.
    @Test func aClosedWindowIsCountedAgainWhenShownAgain() {
        let guests = GuestWindows {}
        let panel = makeWindow()
        guests.add(panel)
        panel.close()

        guests.add(panel)

        #expect(guests.count == 1)
    }

    @Test func anotherWindowClosingChangesNothing() {
        var closes = 0
        let guests = GuestWindows { closes += 1 }
        let panel = makeWindow()
        guests.add(panel)

        makeWindow().close()

        #expect(guests.count == 1)
        #expect(closes == 0)
    }
}
