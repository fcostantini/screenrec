import SwiftUI

@main
struct ScreenRecApp: App {
    var body: some Scene {
        MenuBarExtra("ScreenRec", systemImage: "record.circle") {
            Text("ScreenRec — M0 skeleton")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
