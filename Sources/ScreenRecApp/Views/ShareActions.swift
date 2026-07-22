import AppKit
import Quartz

/// The AppKit share/preview edges for the per-file submenu (M12-T1). Siblings of `Finder`: they live
/// here because AppCore may not import AppKit (docs/01), and the menu view — already in this layer —
/// calls them directly, the `Finder.reveal` precedent (they touch nothing in AppCore).

enum ShareActions {
    /// Writes the file to the pasteboard so ⌘V drops it into Slack/Messages/Finder (docs/06 file item).
    static func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// Opens the OS share sheet (AirDrop/Messages/Mail) for the file. The menu that launched this has
    /// already closed, so the picker anchors to an invisible 1×1 window at the pointer.
    @MainActor static func share(_ url: URL) {
        let view = anchor.place(at: NSEvent.mouseLocation)
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    /// Previews the file in the system Quick Look panel (space toggles, as in Finder).
    @MainActor static func quickLook(_ url: URL) {
        QuickLookController.shared.preview(url)
    }

    @MainActor private static let anchor = AnchorWindow()
}

/// A reused, invisible 1×1 window that anchors a popover/picker which needs a view-in-window but fires
/// from a menu that has already closed (M12-T1 Share…). Repositioned to the pointer on each use; kept
/// around rather than recreated so nothing leaks.
@MainActor private final class AnchorWindow {
    private let window: NSWindow
    private let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))

    init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.contentView = view
    }

    func place(at point: NSPoint) -> NSView {
        window.setFrameOrigin(point)
        window.orderFrontRegardless()
        return view
    }
}

/// Drives the system Quick Look panel for one file from the menu-bar app (M12-T1). The panel's data
/// source is unowned, so this is a held singleton; a `URL` (as `NSURL`) is a `QLPreviewItem`. We're an
/// LSUIElement agent, so the app is activated to bring the panel forward.
private final class QuickLookController: NSObject, QLPreviewPanelDataSource {
    @MainActor static let shared = QuickLookController()

    private var url: URL?

    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url.map { $0 as NSURL }
    }
}
