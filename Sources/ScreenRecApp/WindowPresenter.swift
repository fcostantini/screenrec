import AppCore
import AppKit
import SwiftUI

/// The app's three windows, built without a SwiftUI scene.
///
/// `@Environment(\.openWindow)` is reachable only from a view inside a scene, so none of these may
/// depend on one (M28-T2 removes the last). Each window is built on demand and dropped when it
/// closes, so reopening re-runs its view's `onAppear` — which `TrimView` relies on to rebuild its
/// player.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {

    enum Kind {
        case onboarding, settings, trim
    }

    /// Set by `ScreenRecApp.init` before any window can be asked for. Weak — the App's `@State`
    /// owns it; this is a back-reference, like `AppDelegate.appState`.
    weak var state: AppState?

    private var windows: [Kind: NSWindow] = [:]

    /// Opens the window, or brings an open one forward. An `LSUIElement` app's windows open behind
    /// the frontmost app unless it activates, so presenting always does both.
    func show(_ kind: Kind) {
        guard let state else { return }
        let window = windows[kind] ?? make(kind, state: state)
        windows[kind] = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
    }

    private func make(_ kind: Kind, state: AppState) -> NSWindow {
        switch kind {
        case .onboarding:
            window("Set Up ScreenRec", autosave: "onboarding",
                   hosting: OnboardingView(state: state))
        case .settings:
            window("ScreenRec Settings", autosave: "settings",
                   hosting: SettingsView(state: state))
        case .trim:
            window(trimWindowTitle, autosave: "trim",
                   hosting: TrimView(state: state) { [weak self] in self?.close(.trim) })
        }
    }

    /// Sizes to its content and cannot be resized; `preferredContentSize` is what lets Settings
    /// re-fit when its tab changes. The autosave name keeps a moved window where it was put —
    /// these are rebuilt per open, so nothing else would remember.
    private func window(
        _ title: String, autosave: String, hosting content: some View
    ) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        // The dictionary above owns these; AppKit's release-on-close would free one under ARC.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }
}
