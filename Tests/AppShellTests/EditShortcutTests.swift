import AppKit
import Testing

@testable import AppShell

/// The editing shortcuts an alert's text field answers with no Edit menu behind it (M42-T4).
@MainActor
@Suite struct EditShortcutTests {

    @Test func theSixTheEditMenuBinds() {
        let command = NSEvent.ModifierFlags.command
        #expect(EditShortcut(key: "z", modifiers: command) == .undo)
        #expect(EditShortcut(key: "z", modifiers: [.command, .shift]) == .redo)
        #expect(EditShortcut(key: "x", modifiers: command) == .cut)
        #expect(EditShortcut(key: "c", modifiers: command) == .copy)
        #expect(EditShortcut(key: "v", modifiers: command) == .paste)
        #expect(EditShortcut(key: "a", modifiers: command) == .selectAll)
    }

    /// ⇧⌘Z arrives as "Z", and Caps Lock rides along on every press while it is on.
    @Test func shiftAndCapsLockDoNotHideAShortcut() {
        #expect(EditShortcut(key: "Z", modifiers: [.command, .shift]) == .redo)
        #expect(EditShortcut(key: "v", modifiers: [.command, .capsLock]) == .paste)
    }

    @Test func anythingElseIsLeftAlone() {
        #expect(EditShortcut(key: "v", modifiers: []) == nil)
        #expect(EditShortcut(key: "v", modifiers: .control) == nil)
        #expect(EditShortcut(key: "v", modifiers: [.command, .option]) == nil)
        #expect(EditShortcut(key: "v", modifiers: [.command, .shift]) == nil)
        #expect(EditShortcut(key: "b", modifiers: .command) == nil)
        #expect(EditShortcut(key: "", modifiers: .command) == nil)
    }

    /// Both of the upload sheet's fields are offered every key equivalent; only the one being
    /// typed in may take it.
    @Test func aFieldThatIsNotBeingEditedPassesTheKeyOn() throws {
        let paste = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false,
            keyCode: 9))
        #expect(EditShortcutField().performKeyEquivalent(with: paste) == false)
    }
}
