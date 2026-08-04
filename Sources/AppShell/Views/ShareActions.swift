import AppKit
import Quartz
import RecorderCore

/// The AppKit share/preview edges for the per-file submenu (M12-T1). Siblings of `Finder`: they live
/// here because AppCore may not import AppKit (docs/01), and the menu view — already in this layer —
/// calls them directly, the `Finder.reveal` precedent (they touch nothing in AppCore).

@MainActor
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

    /// Prompts for a new base name (M12-T2) with a modal `NSAlert` + text field — an LSUIElement
    /// app has no window to host a rename, so the alert is it. `newBaseName` fires only on confirm.
    @MainActor static func rename(_ url: URL, newBaseName: (String) -> Void) {
        guard let chosen = askForBaseName(
            of: url, title: "Rename “\(url.lastPathComponent)”",
            message: "The extension stays the same.", confirm: "Rename")
        else { return }
        newBaseName(chosen)
    }

    /// Asks what to call a take that just stopped (M21-T3), labelled with its length so the choice
    /// can be made without opening the file. Nil unless a name was confirmed — Esc and Cancel keep
    /// the date name.
    @MainActor static func nameTake(_ url: URL, duration: TimeInterval) -> String? {
        askForBaseName(
            of: url, title: "Name this recording",
            message: "\(Timecode.length(duration)) · Esc keeps the date name. "
                + "The extension stays the same.",
            confirm: "Name")
    }

    /// The modal both prompts are: a text field pre-filled with `url`'s base name, confirm and
    /// Cancel. Nil unless the confirm button was the one pressed.
    @MainActor private static func askForBaseName(
        of url: URL, title: String, message: String, confirm: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = url.deletingPathExtension().lastPathComponent
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
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
@MainActor
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

    // `QLPreviewPanelDataSource` declares these nonisolated, and QuickLook calls them on the main
    // thread — asserted rather than assumed, so a change of heart by the framework traps here
    // instead of racing on `url`.
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(
        _ panel: QLPreviewPanel!, previewItemAt index: Int
    ) -> (any QLPreviewItem)! {
        // Only the `URL` crosses — it is `Sendable`; `QLPreviewItem` is not, so the `NSURL` is
        // made on this side rather than handed out of the isolated block.
        let url = MainActor.assumeIsolated { self.url }
        return url.map { $0 as NSURL }
    }
}
