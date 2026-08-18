import AppKit
import Testing

@testable import AppCore
@testable import AppShell

/// The menu bar the app shows while a window is open (M37-T1, ADR-023). It exists in code with no
/// nib behind it, so nothing but a test says whether a row is still there.
@MainActor
@Suite struct MainMenuTests {

    private func bar() -> NSMenu {
        MainMenu.make(state: MenuSnapshot.state(), windows: WindowPresenter())
    }

    private func menu(_ title: String) -> NSMenu? {
        bar().item(withTitle: title)?.submenu
    }

    @Test func theBarIsTheThreeDocumentedMenus() {
        #expect(bar().items.compactMap { $0.submenu?.title } == ["ScreenRec", "Edit", "Window"])
    }

    /// 🔴 `install` finds the Window menu **by this title** to hand it to `NSApp.windowsMenu`, which
    /// is what makes AppKit list the open windows. Rename it and the listing silently stops.
    @Test func theWindowMenuIsReachableByTheTitleInstallLooksFor() {
        #expect(bar().item(withTitle: "Window")?.submenu != nil)
    }

    @Test func minimizeAndZoomGoToTheWindow() {
        let window = menu("Window")
        #expect(window?.item(withTitle: "Minimize")?.action == #selector(NSWindow.performMiniaturize(_:)))
        #expect(window?.item(withTitle: "Minimize")?.keyEquivalent == "m")
        #expect(window?.item(withTitle: "Zoom")?.action == #selector(NSWindow.performZoom(_:)))
    }

    /// ⌘W has no File menu to live in, and an app whose windows can't be closed from the keyboard
    /// would be the same papercut this task exists to remove.
    @Test func closeIsBoundEvenThoughThereIsNoFileMenu() {
        let close = menu("Window")?.item(withTitle: "Close")
        #expect(close?.keyEquivalent == "w")
        #expect(close?.action == #selector(NSWindow.performClose(_:)))
    }

    /// The Edit menu's reason for existing: without a bound ⌘V, the `Rename…` field can't be pasted
    /// into, because a text field takes the standard editing commands through menu items only.
    @Test func pasteIsBoundSoATextFieldCanTakeIt() {
        let paste = menu("Edit")?.item(withTitle: "Paste")
        #expect(paste?.keyEquivalent == "v")
        #expect(paste?.action == #selector(NSText.paste(_:)))
    }

    @Test func theEditingRowsCarryNoTargetSoTheResponderChainEnablesThem() {
        let edit = menu("Edit")
        #expect(edit?.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.target == nil } == true)
    }

    @Test func settingsAndQuitCarryTheSameShortcutsAsTheStatusMenu() {
        let app = menu("ScreenRec")
        #expect(app?.item(withTitle: "Settings…")?.keyEquivalent == ",")
        #expect(app?.item(withTitle: "Quit ScreenRec")?.keyEquivalent == "q")
    }

    /// 🔴 Without this conformance ⌘Q stays live *inside* a confirmation alert: automatic enabling
    /// only asks whether the target responds, and a row that is its own target always does.
    @Test func anAppMenuRowValidatesItselfSoAModalSessionCanDimIt() {
        let row = ActionMenuItem("Quit ScreenRec") {}
        #expect(row is NSMenuItemValidation)
        #expect((row as? NSMenuItemValidation)?.validateMenuItem(row) == true)
    }

    /// ⌘Q must not become a second, unguarded way out: quitting mid-recording or mid-export asks
    /// first (docs/06 item 12), and both menus reach that through `QuitFlow`.
    @Test func quitIsARowThatRunsSomethingRatherThanAPlainTerminate() {
        #expect(menu("ScreenRec")?.item(withTitle: "Quit ScreenRec") is ActionMenuItem)
    }
}
