import AppKit

/// Where the Preview window opens, and what of that the user's own placing overrides (docs/06).
///
/// Position and size are kept apart: a move keeps where the window was put while its size goes on
/// following each clip, and only a resize keeps a size. AppKit's frame autosave keeps them together.
@MainActor
enum PreviewPlacement {
    private static let placeName = "preview"
    private static let sizeName = "preview size"

    /// Before the window is shown, so nothing here reads as the user's doing.
    static func place(_ window: NSWindow, fitting clip: CGSize?) {
        let screen = NSScreen.main
        if !window.setFrameUsingName(sizeName) {
            window.setContentSize(
                PreviewLayout.contentSize(clip: clip, visible: screen?.visibleFrame.size ?? .zero))
        }
        let size = window.frame.size
        guard window.setFrameUsingName(placeName) else {
            // `center()` centres on the screen the window is on: put it on the one it was sized for.
            if let screen { window.setFrameOrigin(screen.visibleFrame.origin) }
            return window.center()
        }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let visible = (window.screen ?? screen)?.visibleFrame ?? window.frame
        window.setFrame(
            PreviewLayout.frame(topLeft: topLeft, size: size, visible: visible), display: false)
    }

    static func userMoved(_ window: NSWindow) {
        window.saveFrame(usingName: placeName)
    }

    /// A resize can move the top-left too, so it keeps both.
    static func userResized(_ window: NSWindow) {
        window.saveFrame(usingName: sizeName)
        window.saveFrame(usingName: placeName)
    }
}
