import AppCore
import AppKit

/// A menu row that runs a closure. `NSMenuItem` takes a target/action pair rather than a block; the
/// menu owns its items, so an item is safely its own target.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    /// Invariant: rows are built in code, never decoded from a nib.
    required init(coder: NSCoder) { fatalError("ActionMenuItem is never decoded") }

    @objc private func fire() { run() }
}

/// Row constructors shared by both menus.
///
/// Every menu built here sets `autoenablesItems = false`: AppKit's automatic enabling keys off
/// whether the target responds to the action, which would silently re-enable the dimmed info rows.
@MainActor
enum MenuRow {

    static func menu(_ title: String = "") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        return menu
    }

    static func action(_ title: String, enabled: Bool = true, run: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title, run: run)
        item.isEnabled = enabled
        return item
    }

    /// A dimmed, inert row — docs/06's info rows, which state something rather than doing it.
    static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A row whose colour has to survive: `attributedTitle` is how a menu row is anything but
    /// the default ink (docs/06 "Menu text styling").
    static func destructive(_ title: String, run: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title, run: run)
        item.attributedTitle = NSAttributedString(string: title, attributes: redInk)
        return item
    }

    private static let redInk: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]

    static func check(
        _ title: String, on: Bool, enabled: Bool = true, run: @escaping () -> Void
    ) -> NSMenuItem {
        let item = action(title, enabled: enabled, run: run)
        item.state = on ? .on : .off
        return item
    }

    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = menu(title)
        for child in items { submenu.addItem(child) }
        item.submenu = submenu
        return item
    }

    static func separator() -> NSMenuItem { .separator() }

    /// An action row that advertises its opt-in global shortcut (M12-T3/T6): the shortcut column
    /// when AppKit can map the combo, else a `· ⌥⌘S` title suffix, so the hint never disappears.
    static func action(
        _ title: String, hotkey: Hotkey?, enabled: Bool = true, run: @escaping () -> Void
    ) -> NSMenuItem {
        guard let hotkey else { return action(title, enabled: enabled, run: run) }
        guard let key = HotkeyDisplay.menuKeyEquivalent(for: hotkey) else {
            return action("\(title) · \(HotkeyDisplay.string(for: hotkey))", enabled: enabled, run: run)
        }
        let item = action(title, enabled: enabled, run: run)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = HotkeyDisplay.modifierFlags(for: hotkey)
        return item
    }
}
