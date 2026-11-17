import AppKit

/// A row for a job that knows how far it has got: a track, its fill, and the percentage. The
/// export row while a transcode runs (M28-T4), and the upload row under other words (M40-T4).
///
/// A view row is the only kind that may advance under an open menu — mutating a view rebuilds
/// nothing, which is what the stamped-at-open rule was protecting against (M6-T10, docs/07).
final class ProgressRowView: NSView {

    /// Which job the row follows, so the one to advance is found when both are in the menu.
    enum Kind {
        case export, upload
    }

    static let height: CGFloat = 22
    private static let inset: CGFloat = 21
    private static let gap: CGFloat = 8
    private static let trackHeight: CGFloat = 4
    private static let trackWidth: CGFloat = 110
    /// Fixed, so the row does not resize as the number passes 9% and 99%.
    private static let percentWidth: CGFloat = 38

    let kind: Kind
    private let lead: NSAttributedString
    private let leadSize: NSSize
    /// Drawn after the percentage: `· 1 waiting`.
    private let trailing: NSAttributedString?
    private var fraction: Double

    init(_ kind: Kind = .export, lead: String = "Exporting…", fraction: Double, trailing: String? = nil) {
        self.kind = kind
        self.fraction = fraction
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: NSColor.secondaryLabelColor,
        ]
        self.lead = NSAttributedString(string: lead, attributes: attributes)
        leadSize = self.lead.size()
        self.trailing = trailing.map { NSAttributedString(string: $0, attributes: attributes) }
        let trailingWidth = self.trailing.map { Self.gap + ceil($0.size().width) } ?? 0
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: Self.inset + ceil(leadSize.width) + Self.gap + Self.trackWidth + Self.gap
                + Self.percentWidth + trailingWidth + Self.inset,
            height: Self.height))
    }

    /// Invariant: rows are built in code, never decoded from a nib.
    required init?(coder: NSCoder) { fatalError("ProgressRowView is never decoded") }

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

        if let trailing {
            trailing.draw(at: NSPoint(
                x: track.maxX + Self.gap + Self.percentWidth + Self.gap,
                y: (bounds.height - trailing.size().height) / 2))
        }
    }
}
