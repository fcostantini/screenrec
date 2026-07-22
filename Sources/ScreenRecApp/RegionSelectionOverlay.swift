import AppCore
import AppKit

/// Presents the drag-to-select region overlay (M11-T2) on the main display and hands back the
/// chosen rectangle in SCK `sourceRect` space. AppKit lives here, not in AppCore (docs/01).
///
/// One reused instance (held by the app): it owns the window only while selecting.
final class RegionSelectionController {
    private var window: NSWindow?

    /// Opens the overlay on the main display. `completion` fires once, on confirm, with the
    /// display id and the rect in SCK points (top-left origin, docs/02 §1b); a cancel fires nothing.
    func present(completion: @escaping (CGDirectDisplayID?, CGRect) -> Void) {
        guard window == nil, let screen = Self.mainScreen() else { return }
        let displayID = Self.displayID(of: screen)
        let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onConfirm = { [weak self] viewRect in
            let sourceRect = RegionSelection.sckRect(
                fromViewRect: viewRect, displayHeightPoints: screen.frame.height)
            self?.dismiss()
            completion(displayID, sourceRect)
        }
        view.onCancel = { [weak self] in self?.dismiss() }

        let overlay = OverlayWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.level = .screenSaver           // above the menu bar, so a region can include it
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.contentView = view
        window = overlay

        NSApp.activate(ignoringOtherApps: true)
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    /// The screen backing the main display — the one whose id is `CGMainDisplayID` and whose
    /// AppKit frame is origin-zero, so a view-local drag rect is already display-local.
    private static func mainScreen() -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == CGMainDisplayID() } ?? NSScreen.main
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// A borderless window must opt in to key status, or it never receives Return/Escape.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Draws the dimmed veil with the selection punched through it, tracks the drag, and resolves
/// Return/second-click → confirm, Escape → cancel. Coordinates are AppKit view points
/// (bottom-left origin); the controller flips them to SCK space.
private final class RegionSelectionView: NSView {
    var onConfirm: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    /// The provisional selection, or nil before the first drag. Normalized (positive size).
    private var selection: NSRect?
    private var dragOrigin: NSPoint?
    private var mouseDownPoint: NSPoint?

    /// Below this (points) a drag reads as an accidental click, and a selection reads as too
    /// small to record — the overlay's echo of M11-T1's sub-pixel floor.
    private let minSide: CGFloat = 2
    /// A mouse-up within this of the mouse-down is a click (confirm), not a drag (redraw).
    private let clickSlop: CGFloat = 3

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // Draw the marquee on the very first click even if the overlay appears mid focus-change,
    // instead of spending that click just activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.04, alpha: 0.45).setFill()
        bounds.fill()

        if let selection {
            // Punch the veil so the live screen shows through the selection.
            NSColor.clear.setFill()
            selection.fill(using: .copy)

            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            NSColor.white.setStroke()
            border.stroke()

            drawBadge("\(Int(selection.width.rounded())) × \(Int(selection.height.rounded())) pt",
                      near: selection)
        }

        drawHint("Drag to select a region   ·   Return to confirm   ·   Esc to cancel")
    }

    private func drawBadge(_ text: String, near rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 6
        var origin = NSPoint(x: rect.midX - size.width / 2 - padding, y: rect.minY - size.height - 3 * padding)
        // Keep it on screen when the selection hugs the bottom edge.
        if origin.y < 4 { origin.y = rect.maxY + padding }
        let pill = NSRect(x: origin.x, y: origin.y,
                          width: size.width + 2 * padding, height: size.height + padding)
        NSColor(calibratedWhite: 0.05, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(
            at: NSPoint(x: pill.minX + padding, y: pill.minY + padding / 2), withAttributes: attributes)
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 10
        let pill = NSRect(x: bounds.midX - size.width / 2 - padding, y: bounds.height * 0.08,
                          width: size.width + 2 * padding, height: size.height + padding)
        NSColor(calibratedWhite: 0.05, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(
            at: NSPoint(x: pill.minX + padding, y: pill.minY + padding / 2), withAttributes: attributes)
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        dragOrigin = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        selection = Self.normalized(from: origin, to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil; mouseDownPoint = nil }
        let point = convert(event.locationInWindow, from: nil)
        let moved = hypot(point.x - (mouseDownPoint?.x ?? point.x), point.y - (mouseDownPoint?.y ?? point.y))
        if moved < clickSlop {
            // A click, not a drag: confirm the existing selection (the "second-click confirms" path).
            confirmIfValid()
            return
        }
        selection = Self.normalized(from: dragOrigin ?? point, to: point)
        if let selection, selection.width < minSide || selection.height < minSide { self.selection = nil }
        needsDisplay = true
    }

    // MARK: keys

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()                    // Escape
        case 36, 76: confirmIfValid()           // Return / keypad Enter
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    private func confirmIfValid() {
        guard let selection, selection.width >= minSide, selection.height >= minSide else { return }
        onConfirm?(selection)
    }

    private static func normalized(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
