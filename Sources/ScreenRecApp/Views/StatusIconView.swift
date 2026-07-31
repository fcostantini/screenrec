import AppCore
import AppKit
import RecorderCore
import SwiftUI

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

    /// The status item's accessible name. `Image(nsImage:)` doesn't adopt an `NSImage`'s
    /// `accessibilityDescription` and a label-based `MenuBarExtra` has no title, so the view must
    /// apply this explicitly.
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
    /// ⚠️ A `MenuBarExtra` label renders only its **first** `Image` — a second one contributes
    /// nothing at all (measured: `Text` widens the item, a second `Image` doesn't). So the meter
    /// composites, exactly as the armed badge does.
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
    /// ⚠️ The `.menu` MenuBarExtra hands a label's `Text` to the status item as its AppKit *title*
    /// and discards SwiftUI layout and styling entirely — `.offset`, `.padding` and even a 6 pt
    /// `.font` all render identically (measured, docs/07). That title's digits sit 1.5 px at 2×
    /// above the bar's centre, because digits carry no descenders while the line box reserves room
    /// for them, and nothing in SwiftUI can move it. Drawing the clock here is the only way to put
    /// it on the same optical line as the glyph — the same reason the armed badge and the level
    /// meter composite rather than sit beside it.
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

    /// The save confirmation (M9-T3), composited to the right of everything else — which is where
    /// the original `HStack` put it, and where it never rendered: a `MenuBarExtra` label draws only
    /// its first `Image` (measured, docs/07). Same fix the armed badge and the meter already had.
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

/// The status item's label: the icon (pulsing while recording unless Reduce Motion is on), plus a
/// live elapsed clock (M9-T3) and a brief save confirmation. The clock and flash live here, not in
/// the menu, because the label isn't subject to the `.menu` bridge that freezes the in-menu clock
/// (M6-T10).
struct StatusIconView: View {
    let icon: StatusIcon
    var isReplayArmed = false
    /// An export or trim is running (M23-T3) — orthogonal to the session, like `isReplayArmed`,
    /// so it is a flag rather than a `StatusIcon` case: a take can be recording and exporting.
    var isExporting = false
    var recordingClock: RecordingClock? = nil
    var showsTimer = true
    var replaySavedFlash = false
    /// Pull for the input meter (M16-T5): returns the peak since the last call. Nil ⇒ no meter.
    var microphoneLevel: (() -> Float)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lit bars, updated only when the bucket changes (M16-T5) — never per sample, which is the
    /// M6-T10 rule that also froze the in-menu clock.
    @State private var levelBars = 0

    /// Drives the drawn clock. The text lives inside the icon image now (see `withClock`), so the
    /// tick has to rebuild the image rather than update a `Text`.
    @State private var now = Date()
    private let clockTicker = Timer.publish(
        every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        iconImage
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onReceive(MenuBarLevelMeter.ticker) { _ in
            guard let microphoneLevel else { return }
            let lit = MicrophoneLevel.bars(forPeak: microphoneLevel())
            if lit != levelBars { levelBars = lit }
        }
        .onReceive(clockTicker) { now = $0 }
    }

    /// The elapsed clock to draw beside the glyph, or nil when it isn't shown.
    private var clockText: String? {
        guard showsTimer, let recordingClock else { return nil }
        return Timecode.clock(recordingClock.elapsed(now: now))
    }

    @ViewBuilder private var iconImage: some View {
        if icon == .recording && !reduceMotion {
            PulsingRecordingIcon(
                label: accessibilityLabel, isReplayArmed: isReplayArmed, isExporting: isExporting,
                levelBars: shownBars, clock: clockText, showsSavedMark: replaySavedFlash)
        } else {
            let base = StatusIconImage.image(
                for: icon, isReplayArmed: isReplayArmed, isExporting: isExporting,
                levelBars: shownBars)
            Image(nsImage: Self.decorated(
                base, clock: clockText, showsSavedMark: replaySavedFlash))
        }
    }

    /// The clock and the save mark, in the order the label used to stack them: glyph, then time,
    /// then the tick furthest right.
    static func decorated(_ base: NSImage, clock: String?, showsSavedMark: Bool) -> NSImage {
        var image = clock.map { StatusIconImage.withClock(base, text: $0) } ?? base
        if showsSavedMark { image = StatusIconImage.withSavedMark(image) }
        return image
    }

    /// Nil when the meter is off, which is what tells the drawing to omit it entirely.
    private var shownBars: Int? { microphoneLevel == nil ? nil : levelBars }

    /// The whole item as one VoiceOver element: the icon state, plus elapsed time and a
    /// just-saved note when shown.
    private var accessibilityLabel: String {
        var label = StatusIconImage.label(
            for: icon, isReplayArmed: isReplayArmed, isExporting: isExporting)
        if showsTimer, let recordingClock {
            label += ", " + Timecode.clock(recordingClock.elapsed(now: Date()))
        }
        if replaySavedFlash { label += ", saved" }
        return label
    }
}

/// The live elapsed clock in the status-item label (M9-T3). Redraws once a second off its own
/// The input meter's clock (M16-T5). Polls rather than subscribes: a per-buffer publish is what
/// M6-T10 forbids, and the poll only writes state when the bar count changes — so a silent room
/// costs no redraws at all.
@MainActor
private enum MenuBarLevelMeter {
    static let framesPerSecond: Double = 8
    static let ticker = Timer.publish(
        every: 1 / framesPerSecond, tolerance: 0.02, on: .main, in: .common).autoconnect()
}

/// Redraws the recording icon frame by frame, alive only while recording: SwiftUI's implicit
/// animations don't drive a `MenuBarExtra` label, so the pulse must be timer-driven.
private struct PulsingRecordingIcon: View {
    /// Slow enough to read as breathing rather than as an alert.
    private static let cycle: TimeInterval = 2
    private static let framesPerCycle: Double = 12

    let label: String
    let isReplayArmed: Bool
    let isExporting: Bool
    let levelBars: Int?
    /// Drawn into the image beside the glyph — see `StatusIconImage.withClock`.
    let clock: String?
    let showsSavedMark: Bool

    @State private var phase: Double = 0

    private let ticker = Timer.publish(
        every: cycle / framesPerCycle, tolerance: 0.05, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        let faded = StatusIconImage.recordingImage(
            fadedTo: StatusIconImage.pulseAlpha(atPhase: phase), isReplayArmed: isReplayArmed,
            isExporting: isExporting, levelBars: levelBars)
        Image(nsImage: StatusIconView.decorated(
            faded, clock: clock, showsSavedMark: showsSavedMark))
            .accessibilityLabel(label)
            .onReceive(ticker) { _ in
                phase = (phase + 1 / Self.framesPerCycle).truncatingRemainder(dividingBy: 1)
            }
    }
}
