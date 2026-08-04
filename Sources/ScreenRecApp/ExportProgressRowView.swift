import AppKit

/// The export row while a transcode runs (M28-T4): a track, its fill, and the percentage.
///
/// A view row is the only kind that may advance under an open menu — mutating a view rebuilds
/// nothing, which is what the stamped-at-open rule was protecting against (M6-T10, docs/07).
final class ExportProgressRowView: NSView {

    static let height: CGFloat = 22
    private static let inset: CGFloat = 21
    private static let gap: CGFloat = 8
    private static let trackHeight: CGFloat = 4
    private static let trackWidth: CGFloat = 110
    /// Fixed, so the row does not resize as the number passes 9% and 99%.
    private static let percentWidth: CGFloat = 38

    private let lead: NSAttributedString
    private let leadSize: NSSize
    private var fraction: Double

    init(fraction: Double) {
        self.fraction = fraction
        lead = NSAttributedString(
            string: "Exporting…",
            attributes: [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor])
        leadSize = lead.size()
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: Self.inset + ceil(leadSize.width) + Self.gap + Self.trackWidth + Self.gap
                + Self.percentWidth + Self.inset,
            height: Self.height))
    }

    /// Invariant: rows are built in code, never decoded from a nib.
    required init?(coder: NSCoder) { fatalError("ExportProgressRowView is never decoded") }

    func show(_ fraction: Double) {
        self.fraction = fraction
        needsDisplay = true
    }

    private static let font = NSFont.menuFont(ofSize: 0)

    override func draw(_ dirtyRect: NSRect) {
        lead.draw(at: NSPoint(x: Self.inset, y: (bounds.height - leadSize.height) / 2))

        let track = NSRect(
            x: Self.inset + ceil(leadSize.width) + Self.gap,
            y: (bounds.height - Self.trackHeight) / 2,
            width: Self.trackWidth, height: Self.trackHeight)
        let radius = Self.trackHeight / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let clamped = min(1, max(0, fraction))
        if clamped > 0 {
            var fill = track
            fill.size.width = max(Self.trackHeight, track.width * clamped)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }

        // Tabular figures, so the digits don't shuffle sideways as the number climbs.
        let percent = NSAttributedString(
            string: "\(Int((clamped * 100).rounded()))%",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: Self.font.pointSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        let size = percent.size()
        percent.draw(at: NSPoint(
            x: track.maxX + Self.gap + Self.percentWidth - ceil(size.width),
            y: (bounds.height - size.height) / 2))
    }
}
