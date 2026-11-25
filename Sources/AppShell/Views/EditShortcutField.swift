import AppKit

/// The six editing commands the Edit menu binds. AppKit delivers them to a text field only through
/// that menu's key equivalents, and the app has no menu bar while no window is open (ADR-023).
enum EditShortcut {
    case undo, redo, cut, copy, paste, selectAll

    /// Nil unless the press is exactly one of the six. Caps Lock is not a modifier here.
    init?(key: String, modifiers: NSEvent.ModifierFlags) {
        switch (key.lowercased(), modifiers.intersection([.command, .shift, .option, .control])) {
        case ("z", [.command]): self = .undo
        case ("z", [.command, .shift]): self = .redo
        case ("x", [.command]): self = .cut
        case ("c", [.command]): self = .copy
        case ("v", [.command]): self = .paste
        case ("a", [.command]): self = .selectAll
        default: return nil
        }
    }

    /// `undo:` and `redo:` are responder actions with no Swift declaration to point `#selector` at.
    var action: Selector {
        switch self {
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        }
    }
}

/// A text field for an alert, which can be up with no menu bar behind it: it answers the editing
/// shortcuts itself, the way the Edit menu would — a nil-targeted action down the responder chain.
final class EditShortcutField: NSTextField {

    /// Only while this field is being edited: a key equivalent is offered to every view in the
    /// window, and the upload sheet holds two of these.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard currentEditor() != nil,
              let shortcut = EditShortcut(key: event.characters ?? "", modifiers: event.modifierFlags),
              NSApplication.shared.sendAction(shortcut.action, to: nil, from: self)
        else { return super.performKeyEquivalent(with: event) }
        return true
    }
}
