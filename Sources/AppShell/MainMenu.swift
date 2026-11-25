import AppCore
import AppKit

/// The menu bar, which the app shows only while a window is open (`WindowPolicy`, ADR-023). Built
/// by hand, there being no nib: a `.regular` app with a nil `mainMenu` shows only the Apple menu.
/// Edit is not decoration — a window's text field takes the editing key equivalents only through
/// its rows. An alert's field, which can be up with no bar, answers them itself (`EditShortcut`).
@MainActor
enum MainMenu {

    private static let appName = "ScreenRec"

    /// Installs the bar and hands AppKit the Window menu, which is what makes it list the open
    /// windows itself — minimized ones included, and marked as such.
    ///
    /// Idempotent: AppKit tracks the window list on the menu it was handed, and a rebuild would
    /// throw that away.
    static func install(state: AppState, windows: WindowPresenter) {
        guard NSApplication.shared.mainMenu == nil else { return }
        let bar = make(state: state, windows: windows)
        NSApplication.shared.mainMenu = bar
        NSApplication.shared.windowsMenu = bar.item(withTitle: "Window")?.submenu
    }

    /// 🔴 An `.accessory` app must not keep a bar: its key equivalents fire even though nothing is
    /// drawn, and ⌘H over the region-selection overlay hides that window without closing it, which
    /// strands the pick for the life of the process (docs/07).
    static func remove() {
        NSApplication.shared.mainMenu = nil
        NSApplication.shared.windowsMenu = nil
    }

    /// `NSMenu` directly rather than `MenuRow.menu`, which disables AppKit's automatic enabling:
    /// here it is the point, since Cut/Copy/Paste are only live when a responder can perform them.
    static func make(state: AppState, windows: WindowPresenter) -> NSMenu {
        let bar = NSMenu()
        for menu in [appMenu(state: state, windows: windows), editMenu(), windowMenu()] {
            // The bar matches on the *item's* title, not the submenu's, and `install` looks the
            // Window menu up that way — left unset, AppKit is handed no windows menu at all.
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            bar.addItem(item)
        }
        return bar
    }

    /// AppKit titles the first menu with the process name whatever this says; the title is what the
    /// bar item takes, and how the tests find it.
    private static func appMenu(state: AppState, windows: WindowPresenter) -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(MenuRow.action("About \(appName)") { windows.showAbout() })
        menu.addItem(.separator())
        let settings = MenuRow.action("Settings…") { windows.show(.settings) }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(responderRow("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        let hideOthers = responderRow(
            "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(responderRow("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        let quit = MenuRow.action("Quit \(appName)") { QuitFlow.run(state) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(responderRow("Undo", EditShortcut.undo.action, "z"))
        let redo = responderRow("Redo", EditShortcut.redo.action, "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(responderRow("Cut", EditShortcut.cut.action, "x"))
        menu.addItem(responderRow("Copy", EditShortcut.copy.action, "c"))
        menu.addItem(responderRow("Paste", EditShortcut.paste.action, "v"))
        menu.addItem(responderRow("Select All", EditShortcut.selectAll.action, "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(responderRow("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(responderRow("Zoom", #selector(NSWindow.performZoom(_:))))
        // Close belongs in File by convention, and there is no File menu to put it in — an app with
        // three windows and no documents has nothing else to fill one with.
        menu.addItem(responderRow("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(.separator())
        menu.addItem(responderRow("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    /// A row AppKit routes down the responder chain, which is what enables and disables it — so
    /// these must not carry a target.
    private static func responderRow(
        _ title: String, _ action: Selector, _ key: String = ""
    ) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
