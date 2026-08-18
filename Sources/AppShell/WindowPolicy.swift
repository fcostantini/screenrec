import AppKit

/// Whether the app is in the Dock and ⌘-Tab, given how many of its windows are open (ADR-023).
///
/// `LSUIElement` sets the *launch* state only. Without a Dock tile, a ⌘-Tab entry or a Window menu
/// there is no route back to a minimized window, so an open window earns all three.
enum WindowPolicy {

    static func activationPolicy(openWindows: Int) -> NSApplication.ActivationPolicy {
        openWindows > 0 ? .regular : .accessory
    }
}
