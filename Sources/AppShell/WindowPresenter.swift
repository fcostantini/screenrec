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

    /// Set by `AppDelegate.init` before any window can be asked for. Weak — `AppDelegate.state`
    /// owns it; this is a back-reference.
    weak var state: AppState?

    private var windows: [Kind: NSWindow] = [:]

    /// Opens the window, or brings an open one forward. The app's windows open behind the frontmost
    /// app unless it activates, so presenting always does both — and the policy is set first, so the
    /// Dock tile and menu bar are already there when the window arrives.
    ///
    /// `deminiaturize` because `makeKeyAndOrderFront` is a no-op on a miniaturized window: without it
    /// this row would appear to do nothing when its window is sitting in the Dock.
    func show(_ kind: Kind) {
        guard let state else { return }
        let window = windows[kind] ?? make(kind, state: state)
        windows[kind] = window
        applyActivationPolicy()
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
        // Deferred by a turn: dropping to `.accessory` while the closing window is still on screen
        // leaves the Dock tile and the bar behind. Recomputed when it runs, so opening another
        // window in the meantime is still correct.
        Task { [weak self] in self?.applyActivationPolicy() }
    }

    /// The Dock tile, the ⌘-Tab entry and the menu bar arrive with the first window and leave with
    /// the last (ADR-023) — the bar included, because a bar with nothing drawn still answers its
    /// key equivalents.
    private func applyActivationPolicy() {
        let policy = WindowPolicy.activationPolicy(openWindows: windows.count)
        _ = NSApplication.shared.setActivationPolicy(policy)
        guard policy == .regular else { return MainMenu.remove() }
        guard let state else { return }
        MainMenu.install(state: state, windows: self)
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
            // The only one worth resizing: a crop is drawn on its preview, and a wide clip leaves
            // that preview mostly letterbox at the fitted size (M37-T2).
            window(trimWindowTitle, autosave: "trim", resizable: true,
                   hosting: TrimView(state: state) { [weak self] in self?.close(.trim) })
        }
    }

    /// Sizes to its content unless `resizable`, where the content only sets a floor and the user's
    /// size wins; `preferredContentSize` is what lets Settings re-fit when its tab changes. The
    /// autosave name keeps a moved — and now a resized — window where it was put, since these are
    /// rebuilt per open and nothing else would remember.
    private func window(
        _ title: String, autosave: String, resizable: Bool = false, hosting content: some View
    ) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = resizable ? [.minSize] : [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]
        // The dictionary above owns these; AppKit's release-on-close would free one under ARC.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }
}
