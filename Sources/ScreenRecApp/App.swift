import AppCore
import SwiftUI

/// The menu-bar app (docs/06 "Shell"): no Dock icon, no main window — `LSUIElement` in
/// Info.plist — so the status item and its menu are the entire surface.
///
/// The shell owns the state; the recording controls, source pickers and recent files that fill
/// this menu out arrive with M4-T2, and are what will first drive `AppState` from a live
/// session's event stream.
@main
struct ScreenRecApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            StatusIconView(icon: state.statusIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}
