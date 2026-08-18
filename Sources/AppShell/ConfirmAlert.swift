import AppKit

/// A modal two-button question, reporting whether the **first** button was chosen. Every caller puts
/// the safe choice first, so it is the one Return picks.
///
/// It activates the app first: an alert raised while `.accessory` renders inactive, and its buttons
/// then can't be reached (docs/07).
@MainActor
enum ConfirmAlert {

    static func ask(
        _ message: String, _ informative: String,
        first: String, second: String, secondIsDestructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: first)
        alert.addButton(withTitle: second).hasDestructiveAction = secondIsDestructive
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
