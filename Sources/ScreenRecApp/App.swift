import AppCore
import SwiftUI

/// The menu-bar app (docs/06 "Shell"): no Dock icon, no main window — `LSUIElement` in
/// Info.plist — so the status item and its menu are the entire surface.
///
/// The shell owns the one `AppState`; `MenuView` is the menu, and `StatusIconView` the icon.
@main
struct ScreenRecApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            StatusIconView(icon: state.statusIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}
