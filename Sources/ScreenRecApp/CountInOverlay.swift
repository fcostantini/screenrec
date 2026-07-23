import AppKit

/// The optional 3-2-1 count-in before recording (M12-T6). A big translucent number on the main
/// display, counting down one second per step, then `completion` fires and it dismisses — so the
/// countdown itself is never in the recording. Deliberately **not a veil and click-through**
/// (`ignoresMouseEvents`, ordered front without key): the whole point is to switch to the target
/// window during the beat, so the overlay must not hide the screen or swallow clicks. The
/// `RegionSelectionController` sibling.
final class CountInController {
    private var window: NSWindow?
    private var timer: Timer?

    /// Shows `from` at once, then ticks down one per second; at zero, dismisses and calls `completion`.
    /// A reused instance — a second `run` while one is live is ignored (the `isCountingIn` guard in
    /// AppState already blocks that path). With no main screen, it starts immediately (no count-in).
    func run(from: Int = 3, completion: @escaping () -> Void) {
        guard window == nil else {
            // AppState's `isCountingIn` guard makes this unreachable; assert so a future refactor
            // that broke it surfaces loudly instead of silently wedging Start (dropped completion).
            assertionFailure("count-in re-entered while one is live")
            return
        }
        guard let screen = NSScreen.main else { completion(); return }

        let view = CountInView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.value = from

        let overlay = ClickThroughWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.level = .screenSaver
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true          // the user keeps clicking through to switch windows
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.contentView = view
        overlay.orderFrontRegardless()             // not makeKey — must not steal focus mid-count
        window = overlay

        var remaining = from
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            remaining -= 1
            if remaining > 0 {
                view.value = remaining
                view.needsDisplay = true
            } else {
                self?.dismiss()
                completion()
            }
        }
        // `.common` so opening the menu bar (tracking mode) doesn't freeze the count — the pattern
        // the menu-bar clock already uses (StatusIconView).
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    private func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }
}

/// Click-through by construction — a count-in must never take key/main or block the target window.
private final class ClickThroughWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the current count as a large, soft number centered on the display.
private final class CountInView: NSView {
    var value: Int = 3

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let text = "\(value)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 180, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .shadow: {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
                shadow.shadowBlurRadius = 30
                shadow.shadowOffset = NSSize(width: 0, height: -6)
                return shadow
            }(),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }
}
