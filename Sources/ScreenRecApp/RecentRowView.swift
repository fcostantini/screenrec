import AppKit

/// A recents row: a thumbnail well, the row's title, and its submenu chevron (M28-T3).
///
/// A view-based `NSMenuItem` draws **all** of its own furniture — AppKit contributes no highlight,
/// no checkmark and no chevron (measured, docs/07). The item still carries its `title`, which is
/// what keeps it identical to a plain row under `menudriver`.
final class RecentRowView: NSView {

    static let thumbnailSize = NSSize(width: 36, height: 22)
    static let height: CGFloat = 28
    /// Matches the horizontal inset AppKit gives an ordinary row's title.
    private static let inset: CGFloat = 21
    private static let gap: CGFloat = 8

    let url: URL
    /// Both inks laid out once: `draw(_:)` runs on every highlight change, and measuring text is a
    /// full layout pass.
    private let text: NSAttributedString
    private let highlightedText: NSAttributedString
    private let textSize: NSSize
    private var thumbnail: CGImage?

    init(url: URL, title: String, thumbnail: CGImage?) {
        self.url = url
        self.thumbnail = thumbnail
        text = Self.rendered(title, ink: .labelColor)
        highlightedText = Self.rendered(title, ink: .selectedMenuItemTextColor)
        textSize = text.size()
        super.init(frame: NSRect(
            x: 0, y: 0, width: Self.inset + Self.thumbnailSize.width + Self.gap
                + ceil(text.size().width) + Self.trailing,
            height: Self.height))
        // The width above only sizes the menu; without this each row keeps it, and the chevrons
        // step in and out with the title length instead of lining up at the menu's edge.
        autoresizingMask = [.width]
    }

    /// Invariant: rows are built in code, never decoded from a nib.
    required init?(coder: NSCoder) { fatalError("RecentRowView is never decoded") }

    func show(_ image: CGImage) {
        thumbnail = image
        needsDisplay = true
    }

    private static func rendered(_ title: String, ink: NSColor) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: ink])
    }

    private static let font = NSFont.menuFont(ofSize: 0)
    /// Room for the chevron, so the menu still sizes to its longest row.
    private static let trailing: CGFloat = 28

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }

        let well = NSRect(
            x: Self.inset, y: (bounds.height - Self.thumbnailSize.height) / 2,
            width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        if let thumbnail {
            NSGraphicsContext.current?.cgContext.draw(thumbnail, in: aspectFitted(thumbnail, in: well))
        } else {
            // The well is drawn even when empty, so a row without a readable frame keeps its title
            // in line with the rows around it.
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: well, xRadius: 2, yRadius: 2).fill()
        }

        (highlighted ? highlightedText : text).draw(at: NSPoint(
            x: well.maxX + Self.gap, y: (bounds.height - textSize.height) / 2))

        drawChevron(ink: highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor)
    }

    /// Fills the well while keeping the frame's aspect — a region capture is not 16∶10.
    private func aspectFitted(_ image: CGImage, in well: NSRect) -> NSRect {
        let scale = min(well.width / CGFloat(image.width), well.height / CGFloat(image.height))
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return NSRect(
            x: well.midX - size.width / 2, y: well.midY - size.height / 2,
            width: size.width, height: size.height)
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
