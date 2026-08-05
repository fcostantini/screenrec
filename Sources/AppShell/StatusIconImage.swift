import AppCore
import AppKit
import RecorderCore

/// Draws the status item (docs/06 "Status item").
///
/// Colour is baked into the `NSImage` (`isTemplate = false`) rather than applied with
/// `foregroundStyle`: the menu bar tints template images, so red and amber would come out
/// monochrome.
@MainActor
enum StatusIconImage {

    /// Alpha floor of the recording pulse: it dips, never disappears — blinking fully out reads
    /// as "not recording".
    private static let pulseFloor: Double = 0.45

    /// The status item's accessible name. Its button carries an image and no title, so nothing
    /// supplies one to VoiceOver unless this is set explicitly.
    static func label(
        for icon: StatusIcon, isReplayArmed: Bool, isExporting: Bool = false
    ) -> String {
        let base = switch icon {
        case .idle: "ScreenRec: ready"
        case .recording: "ScreenRec: recording"
        case .paused: "ScreenRec: paused"
        }
        var label = isReplayArmed ? base + ", replay armed" : base
        if isExporting { label += ", exporting" }
        return label
    }

    // Built once each; the pulse would otherwise redo the lookup and palette render every frame.
    // Only the bare glyphs are cached — badges are two filled ovals, far cheaper than a symbol
    // lookup, and caching every combination of them would be six images to keep in step.
    private static let idleImage = template("record.circle")
    private static let recordingImage = tinted("record.circle.fill", .systemRed)
    private static let pausedImage = tinted("circle.lefthalf.filled", .systemOrange)

    private static func glyph(for icon: StatusIcon) -> NSImage {
        switch icon {
        case .idle: idleImage
        case .recording: recordingImage
        case .paused: pausedImage
        }
    }

    static func image(
        for icon: StatusIcon, isReplayArmed: Bool = false, isExporting: Bool = false,
        levelBars: Int? = nil
    ) -> NSImage {
        let base = badged(glyph(for: icon), armed: isReplayArmed, exporting: isExporting)
        guard let levelBars else { return base }
        return withMeter(base, bars: levelBars)
    }

    /// The recording icon faded for the pulse; `alpha` comes from `pulseAlpha(atPhase:)`.
    /// Badges do not fade — armed and exporting are steady states, only recording breathes.
    static func recordingImage(
        fadedTo alpha: Double, isReplayArmed: Bool = false, isExporting: Bool = false,
        levelBars: Int? = nil
    ) -> NSImage {
        let base = recordingImage
        guard alpha < 1 else {
            return image(
                for: .recording, isReplayArmed: isReplayArmed, isExporting: isExporting,
                levelBars: levelBars)
        }
        // `NSImage(size:flipped:)` re-renders per representation, so the fade survives a scale
        // change between Retina and non-Retina displays.
        let faded = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: rect, operation: .sourceOver, fraction: alpha)
            drawBadges(in: rect, armed: isReplayArmed, exporting: isExporting, onTemplate: false)
            return true
        }
        faded.isTemplate = base.isTemplate
        guard let levelBars else { return faded }
        return withMeter(faded, bars: levelBars)
    }

    /// Which corner a badge sits in. Two overlays share the glyph, so they cannot share a corner:
    /// armed keeps the one it has shipped in since M5, and exporting takes the other.
    private enum BadgeCorner {
        case bottomTrailing   // replay armed (docs/06 status-item row 6)
        case topTrailing      // an export in flight (M23-T3)
    }

    /// docs/06 status-item rows 6–7: small filled dots. Template bases keep the badge in the mask
    /// (it adapts with the bar); colored bases get a white dot with a clear gap so it reads against
    /// red and amber alike.
    private static func badged(_ base: NSImage, armed: Bool, exporting: Bool) -> NSImage {
        guard armed || exporting else { return base }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            drawBadges(
                in: rect, armed: armed, exporting: exporting, onTemplate: base.isTemplate)
            return true
        }
        image.isTemplate = base.isTemplate
        return image
    }

    private static func drawBadges(
        in rect: NSRect, armed: Bool, exporting: Bool, onTemplate: Bool
    ) {
        if armed { drawBadge(in: rect, corner: .bottomTrailing, onTemplate: onTemplate) }
        if exporting { drawBadge(in: rect, corner: .topTrailing, onTemplate: onTemplate) }
    }

    private static func drawBadge(in rect: NSRect, corner: BadgeCorner, onTemplate: Bool) {
        let diameter = rect.width * 0.38
        let y = switch corner {
        case .bottomTrailing: rect.minY
        case .topTrailing: rect.maxY - diameter
        }
        let badgeRect = NSRect(
            x: rect.maxX - diameter, y: y, width: diameter, height: diameter)
        // The gap ring separates the dot from the glyph; in a template it's punched out of the
        // mask, on a colored base it clears whatever is behind.
        NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        (onTemplate ? NSColor.black : NSColor.white).setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
    }

    /// The input meter (M16-T5), drawn INTO the icon rather than beside it.
    ///
    /// ⚠️ The status item's button carries **one** image, so anything that must appear beside the
    /// glyph is composited into it rather than added alongside — as the armed badge already is.
    private static func withMeter(_ base: NSImage, bars: Int) -> NSImage {
        let gap: CGFloat = 3, meterWidth: CGFloat = 9
        let size = NSSize(width: base.size.width + gap + meterWidth, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(
                in: NSRect(origin: .zero, size: base.size),
                from: .zero, operation: .sourceOver, fraction: 1)
            drawMeter(
                bars: bars,
                in: NSRect(x: base.size.width + gap, y: 0, width: meterWidth, height: size.height),
                onTemplate: base.isTemplate)
            return true
        }
        image.isTemplate = base.isTemplate
        return image
    }

    /// Three bars of rising height; lit ones solid, unlit ones faint. Colour is deliberately not
    /// used: the idle icon is a template, where only the alpha channel survives.
    private static func drawMeter(bars: Int, in rect: NSRect, onTemplate: Bool) {
        let barWidth: CGFloat = 2, gap: CGFloat = 1.5
        let ink = onTemplate ? NSColor.black : NSColor.white
        for index in 0..<MicrophoneLevel.barCount {
            let barHeight = rect.height * (0.3 + 0.22 * CGFloat(index))
            let bar = NSRect(
                x: rect.minX + CGFloat(index) * (barWidth + gap), y: rect.minY,
                width: barWidth, height: barHeight)
            ink.withAlphaComponent(index < bars ? 1 : 0.28).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 0.8, yRadius: 0.8).fill()
        }
    }

    /// Draws the elapsed clock **into** the icon image, instead of letting the label carry a
    /// `Text`.
    ///
    /// ⚠️ A button *title* sits on the text baseline, which puts its digits 1.5 px at 2× above the
    /// bar's centre: digits carry no descenders while the line box reserves room for them (measured,
    /// docs/07). Drawing the clock into the image is what puts it on the same optical line as the
    /// glyph — the same reason the armed badge and the level meter composite rather than sit beside.
    ///
    /// Centred on the digits' **cap height**, not the line box, which is the whole point.
    static func withClock(_ base: NSImage, text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: adaptiveInk(onTemplate: base.isTemplate),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let gap: CGFloat = 4

        let size = NSSize(width: base.size.width + gap + ceil(textSize.width), height: base.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(
                in: NSRect(origin: .zero, size: base.size), from: .zero,
                operation: .sourceOver, fraction: 1)
            // Baseline placed so the cap-height box straddles the centre; `draw(at:)` takes the
            // line's bottom-left, which is the baseline plus the (negative) descender.
            let baseline = (size.height - font.capHeight) / 2
            string.draw(at: NSPoint(x: base.size.width + gap, y: baseline + font.descender))
            return true
        }
        image.isTemplate = base.isTemplate
        return image
    }

    /// The save confirmation (M9-T3), composited to the right of everything else — the button holds
    /// a single image, so this rides in it like the armed badge and the meter.
    static func withSavedMark(_ base: NSImage) -> NSImage {
        let gap: CGFloat = 3
        let diameter = min(base.size.height, base.size.width) * 0.62
        let size = NSSize(width: base.size.width + gap + diameter, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(
                in: NSRect(origin: .zero, size: base.size),
                from: .zero, operation: .sourceOver, fraction: 1)
            let box = NSRect(
                x: base.size.width + gap, y: (size.height - diameter) / 2,
                width: diameter, height: diameter)
            drawCheck(in: box, onTemplate: base.isTemplate)
            return true
        }
        image.isTemplate = base.isTemplate
        return image
    }

    /// A tick, stroked rather than a filled symbol: at menu-bar size a glyph's own padding leaves
    /// it visibly smaller than the record circle beside it.
    private static func drawCheck(in rect: NSRect, onTemplate: Bool) {
        let ink = adaptiveInk(onTemplate: onTemplate)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.14, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.24))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.88, y: rect.maxY - rect.height * 0.20))
        path.lineWidth = max(1.5, rect.width * 0.16)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        ink.setStroke()
        path.stroke()
    }

    /// Ink for anything drawn beside the glyph. A template is masked by the menu bar, which tints
    /// it; a colored image isn't, so its ink has to follow the effective appearance itself.
    private static func adaptiveInk(onTemplate: Bool) -> NSColor {
        guard !onTemplate else { return .black }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white : .black
    }

    /// Maps the pulse's phase in [0,1) to an alpha: a raised cosine, so it eases at both ends.
    static func pulseAlpha(atPhase phase: Double) -> Double {
        let eased = (1 + cos(2 * .pi * phase)) / 2      // 1 → 0 → 1 over the cycle
        return pulseFloor + (1 - pulseFloor) * eased
    }

    /// The clock and the save mark, in the order they stack: glyph, then time, then the tick
    /// furthest right.
    static func decorated(_ base: NSImage, clock: String?, showsSavedMark: Bool) -> NSImage {
        var image = clock.map { withClock(base, text: $0) } ?? base
        if showsSavedMark { image = withSavedMark(image) }
        return image
    }

    /// Idle stays a template: the system tints it for light/dark and menu-bar highlight.
    private static func template(_ name: String) -> NSImage {
        // Invariant: every name passed here is a compile-time constant present in macOS 15, the
        // deployment target, so the lookup cannot fail. Description nil is deliberate; see
        // `label(for:)`.
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }

    private static func tinted(_ name: String, _ color: NSColor) -> NSImage {
        let base = template(name)
        // Degrade rather than trap: losing the colour is cosmetic, and this runs on the
        // start/pause path, not a preflight.
        guard let coloured = base.withSymbolConfiguration(.init(paletteColors: [color])) else {
            return base
        }
        coloured.isTemplate = false        // keep the colour; see the type comment
        return coloured
    }
}
