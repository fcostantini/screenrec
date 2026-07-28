import AppCore
import AppKit
import Carbon.HIToolbox

/// The optional 3-2-1 count-in before recording (M12-T6). A big translucent number on the main
/// display, counting down one second per step, then `completion` fires and it dismisses — so the
/// countdown itself is never in the recording. Deliberately **not a veil and click-through**
/// (`ignoresMouseEvents`, ordered front without key): the whole point is to switch to the target
/// window during the beat, so the overlay must not hide the screen or swallow clicks. The
/// `RegionSelectionController` sibling.
@MainActor
final class CountInController {
    private var window: NSWindow?
    private var timer: Timer?
    private let hotkeys: HotkeyCenter

    /// Esc, no modifiers. The overlay never becomes key (it must not steal focus mid-count), so no
    /// key event reaches it — a Carbon hotkey is the one global route that needs no TCC grant
    /// (02 §9). It is registered only while a count is live, since it swallows Esc system-wide.
    private static let escape = Hotkey(keyCode: kVK_Escape, modifiers: 0)
    private static let escapeHotkeyID: UInt32 = 4

    init(hotkeys: HotkeyCenter) {
        self.hotkeys = hotkeys
    }

    /// Shows `from` at once, then ticks down one per second; at zero, dismisses and reports
    /// `.finished`. Esc dismisses it early and reports `.cancelled`, so nothing is recorded.
    /// A reused instance — a second `run` while one is live is ignored (the `isCountingIn` guard in
    /// AppState already blocks that path). With no main screen, it starts immediately (no count-in).
    func run(from: Int = 3, completion: @escaping @MainActor (CountInOutcome) -> Void) {
        guard window == nil else {
            // AppState's `isCountingIn` guard makes this unreachable; assert so a future refactor
            // that broke it surfaces loudly instead of silently wedging Start (dropped completion).
            assertionFailure("count-in re-entered while one is live")
            return
        }
        guard let screen = NSScreen.main else { completion(.finished); return }

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
                // The timer is scheduled on RunLoop.main, so this body is already on the main
                // thread; the isolation is provable, not assumed.
                MainActor.assumeIsolated {
                    self?.dismiss()
                    completion(.finished)
                }
            }
        }
        // `.common` so opening the menu bar (tracking mode) doesn't freeze the count — the pattern
        // the menu-bar clock already uses (StatusIconView).
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker

        hotkeys.setHotkey(Self.escape, id: Self.escapeHotkeyID) { [weak self] in
            guard let self, window != nil else { return }
            dismiss()
            completion(.cancelled)
        }
    }

    private func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        hotkeys.setHotkey(nil, id: Self.escapeHotkeyID)   // Esc belongs to everyone else again
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
