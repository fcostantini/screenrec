import AppKit

/// Windows the app counts as open without having built them (ADR-023) — the Quick Look panel and
/// the About panel, which are the system's. One is counted until it closes: `willCloseNotification`
/// is not posted when another app comes in front, so it stays counted behind that app (docs/07).
@MainActor
final class GuestWindows: NSObject {

    private var counted: [NSWindow] = []
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
        super.init()
    }

    var count: Int { counted.count }

    /// Idempotent: the shared panel is presented again for every file previewed.
    func add(_ window: NSWindow) {
        guard !counted.contains(where: { $0 === window }) else { return }
        counted.append(window)
        // Selector-based, so the registration goes when this object does.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification,
            object: window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              let index = counted.firstIndex(where: { $0 === closing })
        else { return }
        counted.remove(at: index)
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.willCloseNotification, object: closing)
        onClose()
    }
}
