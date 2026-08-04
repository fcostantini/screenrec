import AppKit

/// A recents row: a thumbnail well, the row's title, and its submenu chevron (M28-T3).
///
/// A view-based `NSMenuItem` draws **all** of its own furniture — AppKit contributes no highlight,
/// no checkmark and no chevron (measured, docs/07). The item still carries its `title`, which is
/// what keeps it identical to a plain row under `menudriver`.
final class RecentRowView: NSView {

    static let thumbnailSize = NSSize(width: 36, height: 22)
    static let height: CGFloat = 28
    /// Room for the chevron, so the menu still sizes to its longest row.
    fileprivate static let trailing: CGFloat = 28

    /// The furniture plus the title's own width. Static so it can be checked without a row.
    static func width(forTitleWidth titleWidth: CGFloat) -> CGFloat {
        inset + thumbnailSize.width + gap + ceil(titleWidth) + trailing
    }

    /// Fills the well while keeping the frame's aspect — a region capture is not 16∶10.
    static func aspectFitted(_ image: NSSize, in well: NSRect) -> NSRect {
        let scale = min(well.width / image.width, well.height / image.height)
        let size = NSSize(width: image.width * scale, height: image.height * scale)
        return NSRect(
            x: well.midX - size.width / 2, y: well.midY - size.height / 2,
            width: size.width, height: size.height)
    }
    /// AppKit insets a row's own highlight by this much; measured against one it draws itself.
    fileprivate static let highlightInset: CGFloat = 5
    fileprivate static let inset: CGFloat = 21
    fileprivate static let gap: CGFloat = 8

    let url: URL
    /// The selection is a vibrancy material, not a fill: a flat colour measures visibly different
    /// beside an AppKit-drawn row, which is what `selectedMenuItemColor` was deprecated in favour of.
    private let selection = NSVisualEffectView()
    private let content: RowContent

    init(url: URL, title: String, thumbnail: CGImage?) {
        self.url = url
        content = RowContent(title: title, thumbnail: thumbnail)
        super.init(frame: NSRect(x: 0, y: 0, width: content.width, height: Self.height))
        // The width above only sizes the menu; without this each row keeps it, and the chevrons
        // step in and out with the title length instead of lining up at the menu's edge.
        autoresizingMask = [.width]

        selection.material = .selection
        selection.state = .active
        selection.isEmphasized = true
        selection.blendingMode = .behindWindow
        selection.wantsLayer = true
        selection.layer?.cornerRadius = 4
        selection.isHidden = true
        addSubview(selection)
        addSubview(content)
    }

    /// Invariant: rows are built in code, never decoded from a nib.
    required init?(coder: NSCoder) { fatalError("RecentRowView is never decoded") }

    func show(_ image: CGImage) { content.show(image) }

    override func layout() {
        super.layout()
        selection.frame = bounds.insetBy(dx: Self.highlightInset, dy: 0)
        content.frame = bounds
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        selection.isHidden = !highlighted
        content.setHighlighted(highlighted)
    }
}

/// The row's ink, over the selection material rather than under it: a subview draws above its
/// superview, so the two cannot share one view.
private final class RowContent: NSView {

    private let text: NSAttributedString
    private let highlightedText: NSAttributedString
    private let textSize: NSSize
    private var thumbnail: CGImage?
    private var highlighted = false

    let width: CGFloat

    init(title: String, thumbnail: CGImage?) {
        self.thumbnail = thumbnail
        text = Self.rendered(title, ink: .labelColor)
        highlightedText = Self.rendered(title, ink: .selectedMenuItemTextColor)
        textSize = text.size()
        width = RecentRowView.width(forTitleWidth: textSize.width)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: RecentRowView.height))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("RowContent is never decoded") }

    func show(_ image: CGImage) {
        thumbnail = image
        needsDisplay = true
    }

    func setHighlighted(_ value: Bool) {
        guard value != highlighted else { return }
        highlighted = value
        needsDisplay = true
    }

    private static func rendered(_ title: String, ink: NSColor) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: ink])
    }

    private static let font = NSFont.menuFont(ofSize: 0)

    override func draw(_ dirtyRect: NSRect) {
        let well = NSRect(
            x: RecentRowView.inset,
            y: (bounds.height - RecentRowView.thumbnailSize.height) / 2,
            width: RecentRowView.thumbnailSize.width, height: RecentRowView.thumbnailSize.height)
        if let thumbnail {
            let size = NSSize(width: thumbnail.width, height: thumbnail.height)
            NSGraphicsContext.current?.cgContext.draw(
                thumbnail, in: RecentRowView.aspectFitted(size, in: well))
        } else {
            // The well is drawn even when empty, so a row without a readable frame keeps its title
            // in line with the rows around it.
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: well, xRadius: 2, yRadius: 2).fill()
        }

        (highlighted ? highlightedText : text).draw(at: NSPoint(
            x: well.maxX + RecentRowView.gap, y: (bounds.height - textSize.height) / 2))

        drawChevron(ink: highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor)
    }

    private func drawChevron(ink: NSColor) {
        let right = bounds.maxX - 14
        let middle = bounds.midY
        let arm: CGFloat = 3.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: right - arm, y: middle + arm))
        path.line(to: NSPoint(x: right, y: middle))
        path.line(to: NSPoint(x: right - arm, y: middle - arm))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        ink.setStroke()
        path.stroke()
    }
}
