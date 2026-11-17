import AppCore
import AppKit
import Quartz
import RecorderCore
import UploadCore

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

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

    /// Says what the browser step is before any browser opens (M40-T3). True only on the confirm.
    @MainActor static func confirmConnect() -> Bool {
        let alert = NSAlert()
        alert.messageText = UploadCopy.connectTitle
        alert.informativeText = UploadCopy.connectMessage
        alert.addButton(withTitle: UploadCopy.connectConfirm)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// The upload sheet (M40-T3, docs/06): title, description and visibility — the three things
    /// YouTube's terms say an upload client must let the user set. Nil unless `Upload` was pressed.
    @MainActor static func askForUpload(_ draft: UploadDraft) -> VideoMetadata? {
        let alert = NSAlert()
        alert.messageText = UploadCopy.sheetTitle
        alert.informativeText = draft.summary
        let confirm = alert.addButton(withTitle: UploadCopy.sheetConfirm)
        alert.addButton(withTitle: "Cancel")

        let form = UploadFormView(draft: draft, confirm: confirm)
        alert.accessoryView = form
        alert.window.initialFirstResponder = form.titleField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return form.metadata(fallbackTitle: draft.title)
    }

    /// The account step every upload starts with (M40-T3/T4), then `present`: at once when an
    /// account is connected; after the connect alert and the sign-in when none is — and then
    /// only if `stillWanted`, since the browser trip is long enough for its reason to go. A
    /// sign-in that failed or was given up leaves the account saying why.
    @MainActor static func beginUpload(
        _ uploads: UploadModel, stillWanted: @escaping @MainActor () -> Bool,
        present: @escaping @MainActor () -> Void
    ) {
        switch UploadCopy.trimAction(uploads.account, canSignIn: uploads.canSignIn) {
        case .upload:
            present()
        case .connect:
            guard confirmConnect() else { return }
            Task { @MainActor in
                await uploads.connectAndWait()
                guard UploadCopy.trimAction(uploads.account, canSignIn: uploads.canSignIn) == .upload,
                      stillWanted()
                else { return }
                present()
            }
        case .cancelSignIn:
            uploads.cancelConnect()
        case .none:
            break
        }
    }

    /// `Try Again` on the failed upload's row (M40-T6): the account step first when there is no
    /// account, then the retry — if this is still the failure the row was built for.
    @MainActor static func tryAgain(_ failed: FailedUpload, state: AppState) {
        let stillThis: @MainActor () -> Bool = { state.uploads.failedUpload?.id == failed.id }
        guard stillThis() else { return }
        beginUpload(state.uploads, stillWanted: stillThis) {
            guard stillThis() else { return }
            state.uploads.tryAgain()
        }
    }

    /// Raised from a press on the menu's row until its sheet has been answered. The menu stays
    /// usable while the clip's length is read and while the sheet is up, and a second press must
    /// not stack a second sheet — two confirmed sheets are the same clip uploaded twice.
    @MainActor private static var isAskingForUpload = false

    /// `Upload to YouTube…` on a clip the menu lists (M40-T4): the sheet, then the file as it is.
    @MainActor static func upload(_ file: URL, state: AppState) {
        guard !isAskingForUpload else { return }
        let exists: @MainActor () -> Bool = { FileManager.default.fileExists(atPath: file.path) }
        beginUpload(state.uploads, stillWanted: exists) {
            guard !isAskingForUpload else { return }
            isAskingForUpload = true
            Task { @MainActor in
                defer { isAskingForUpload = false }
                // The length is a header read; the sheet waits for it rather than quote nothing.
                let seconds = await MediaFile.duration(of: file)
                guard exists() else { return }
                let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init)
                let draft = UploadDraft(
                    title: UploadForm.defaultTitle(forExport: file),
                    privacy: state.uploadVisibility,
                    summary: UploadCopy.fileSummary(seconds: seconds, bytes: bytes),
                    channel: state.uploads.channelTitle,
                    isLong: seconds.map(UploadForm.isLong) ?? false)
                guard let metadata = askForUpload(draft) else { return }
                state.uploadFile(file, metadata: metadata)
            }
        }
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

/// The upload sheet's fields, as an alert's accessory view. It only *applies* `UploadForm`'s rules
/// — as the user types, so a title YouTube would refuse can't be sent — and holds none of its own.
@MainActor
private final class UploadFormView: NSView, NSTextFieldDelegate {
    let titleField = NSTextField()
    private let descriptionField = NSTextField()
    private let visibility = NSPopUpButton()
    private let visibilityCaption = NSTextField(wrappingLabelWithString: "")
    private let confirm: NSButton

    private static let width: CGFloat = 300

    init(draft: UploadDraft, confirm: NSButton) {
        self.confirm = confirm
        super.init(frame: .zero)

        titleField.stringValue = draft.title
        titleField.delegate = self
        titleField.setAccessibilityLabel("Title")

        descriptionField.placeholderString = "Optional"
        descriptionField.usesSingleLineMode = false
        descriptionField.lineBreakMode = .byWordWrapping
        descriptionField.cell?.wraps = true
        descriptionField.cell?.isScrollable = false
        descriptionField.delegate = self
        descriptionField.setAccessibilityLabel("Description")

        visibility.addItems(withTitles: UploadCopy.visibilityChoices.map(UploadCopy.visibilityLabel))
        visibility.selectItem(at: UploadCopy.visibilityChoices.firstIndex(of: draft.privacy) ?? 0)
        visibility.target = self
        visibility.action = #selector(visibilityChanged)
        visibility.setAccessibilityLabel("Visibility")

        var rows: [NSView] = [
            Self.label("Title"), titleField,
            Self.label("Description"), descriptionField,
            Self.label("Visibility"), visibility, visibilityCaption,
            Self.caption(UploadCopy.sheetDestination(channel: draft.channel)),
        ]
        if draft.isLong { rows.append(Self.caption(UploadCopy.longVideoWarning)) }
        Self.style(visibilityCaption)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
            titleField.widthAnchor.constraint(equalToConstant: Self.width),
            descriptionField.widthAnchor.constraint(equalToConstant: Self.width),
            descriptionField.heightAnchor.constraint(equalToConstant: 54),
        ])
        // An accessory view is placed by its frame, so the layout has to be settled into one —
        // after the captions have their text, or the frame comes out a line short and clips the
        // top row.
        refresh()
        layoutSubtreeIfNeeded()
        frame.size = NSSize(width: Self.width, height: stack.fittingSize.height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UploadFormView is built in code")
    }

    func metadata(fallbackTitle: String) -> VideoMetadata {
        UploadForm.metadata(
            title: titleField.stringValue, description: descriptionField.stringValue,
            privacy: privacy, fallbackTitle: fallbackTitle)
    }

    private var privacy: VideoMetadata.Privacy {
        let choices = UploadCopy.visibilityChoices
        let index = visibility.indexOfSelectedItem
        return choices.indices.contains(index) ? choices[index] : choices[0]
    }

    func controlTextDidChange(_ notification: Notification) {
        refresh()
    }

    @objc private func visibilityChanged() {
        refresh()
    }

    private func refresh() {
        apply(UploadForm.title, to: titleField)
        apply(UploadForm.description, to: descriptionField)
        confirm.isEnabled = UploadForm.canUpload(title: UploadForm.title(titleField.stringValue))
        visibilityCaption.stringValue = UploadCopy.visibilityCaption(privacy)
    }

    /// Rewrites `field` only where `rule` changes it, and puts the insertion point back: assigning
    /// `stringValue` sends it to the end.
    private func apply(_ rule: (String) -> String, to field: NSTextField) {
        let editor = field.currentEditor() as? NSTextView
        // An input method's composition isn't text yet, and assigning over it would discard it.
        // The rules meet it when it commits.
        guard editor?.hasMarkedText() != true else { return }
        let text = field.stringValue
        let ruled = rule(text)
        guard ruled != text else { return }
        let caret = editor.map {
            UploadForm.caret($0.selectedRange().location, in: text, after: rule)
        }
        field.stringValue = ruled
        if let caret {
            field.currentEditor()?.selectedRange = NSRange(location: caret, length: 0)
        }
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        style(label)
        return label
    }

    private static func caption(_ text: String) -> NSTextField {
        let caption = NSTextField(wrappingLabelWithString: text)
        style(caption)
        return caption
    }

    private static func style(_ field: NSTextField) {
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = width
    }
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
