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
    static func label(for icon: StatusIcon, isReplayArmed: Bool) -> String {
        let base = switch icon {
        case .idle: "ScreenRec: ready"
        case .recording: "ScreenRec: recording"
        case .paused: "ScreenRec: paused"
        }
        return isReplayArmed ? base + ", replay armed" : base
    }

    // Built once each; the pulse would otherwise redo the lookup and palette render every frame.
    private static let idleImage = template("record.circle")
    private static let recordingImage = tinted("record.circle.fill", .systemRed)
    private static let pausedImage = tinted("circle.lefthalf.filled", .systemOrange)
    private static let idleArmedImage = badged(template("record.circle"))
    private static let recordingArmedImage = badged(tinted("record.circle.fill", .systemRed))
    private static let pausedArmedImage = badged(tinted("circle.lefthalf.filled", .systemOrange))

    static func image(
        for icon: StatusIcon, isReplayArmed: Bool = false, levelBars: Int? = nil
    ) -> NSImage {
        let base = switch (icon, isReplayArmed) {
        case (.idle, false): idleImage
        case (.recording, false): recordingImage
        case (.paused, false): pausedImage
        case (.idle, true): idleArmedImage
        case (.recording, true): recordingArmedImage
        case (.paused, true): pausedArmedImage
        }
        guard let levelBars else { return base }
        return withMeter(base, bars: levelBars)
    }

    /// The recording icon faded for the pulse; `alpha` comes from `pulseAlpha(atPhase:)`.
    /// The armed badge does not fade — armed is a steady state, only recording breathes.
    static func recordingImage(
        fadedTo alpha: Double, isReplayArmed: Bool = false, levelBars: Int? = nil
    ) -> NSImage {
        let base = recordingImage
        guard alpha < 1 else {
            return image(for: .recording, isReplayArmed: isReplayArmed, levelBars: levelBars)
        }
        // `NSImage(size:flipped:)` re-renders per representation, so the fade survives a scale
        // change between Retina and non-Retina displays.
        let faded = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            if isReplayArmed { drawBadge(in: rect, onTemplate: false) }
            return true
        }
        faded.isTemplate = base.isTemplate
        guard let levelBars else { return faded }
        return withMeter(faded, bars: levelBars)
    }

    /// docs/06 status-item row 4: a small filled dot, bottom-trailing. Template bases keep the
    /// badge in the mask (it adapts with the bar); colored bases get a white dot with a clear
    /// gap so it reads against red and amber alike.
    private static func badged(_ base: NSImage) -> NSImage {
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            drawBadge(in: rect, onTemplate: base.isTemplate)
            return true
        }
        image.isTemplate = base.isTemplate
        return image
    }

    private static func drawBadge(in rect: NSRect, onTemplate: Bool) {
        let diameter = rect.width * 0.38
        let badgeRect = NSRect(
            x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter)
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
    var recordingClock: RecordingClock? = nil
    var showsTimer = true
    var replaySavedFlash = false
    var markAddedFlash = false
    /// Pull for the input meter (M16-T5): returns the peak since the last call. Nil ⇒ no meter.
    var microphoneLevel: (() -> Float)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lit bars, updated only when the bucket changes (M16-T5) — never per sample, which is the
    /// M6-T10 rule that also froze the in-menu clock.
    @State private var levelBars = 0

    var body: some View {
        HStack(spacing: 4) {
            iconImage
            if showsTimer, let recordingClock {
                MenuBarTimer(clock: recordingClock)
            }
            if replaySavedFlash {
                Image(systemName: "checkmark.circle.fill")
            }
            if markAddedFlash {
                Image(systemName: "bookmark.fill")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onReceive(MenuBarLevelMeter.ticker) { _ in
            guard let microphoneLevel else { return }
            let lit = MicrophoneLevel.bars(forPeak: microphoneLevel())
            if lit != levelBars { levelBars = lit }
        }
    }

    @ViewBuilder private var iconImage: some View {
        if icon == .recording && !reduceMotion {
            PulsingRecordingIcon(
                label: StatusIconImage.label(for: icon, isReplayArmed: isReplayArmed),
                isReplayArmed: isReplayArmed, levelBars: shownBars)
        } else {
            Image(nsImage: StatusIconImage.image(
                for: icon, isReplayArmed: isReplayArmed, levelBars: shownBars))
        }
    }

    /// Nil when the meter is off, which is what tells the drawing to omit it entirely.
    private var shownBars: Int? { microphoneLevel == nil ? nil : levelBars }

    /// The whole item as one VoiceOver element: the icon state, plus elapsed time and a
    /// just-saved note when shown.
    private var accessibilityLabel: String {
        var label = StatusIconImage.label(for: icon, isReplayArmed: isReplayArmed)
        if showsTimer, let recordingClock {
            label += ", " + Timecode.clock(recordingClock.elapsed(now: Date()))
        }
        if replaySavedFlash { label += ", replay saved" }
        if markAddedFlash { label += ", mark added" }
        return label
    }
}

/// The live elapsed clock in the status-item label (M9-T3). Redraws once a second off its own
/// timer; a paused clock (`runningSince == nil`) yields a constant value, so it simply freezes.
private struct MenuBarTimer: View {
    let clock: RecordingClock
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(Timecode.clock(clock.elapsed(now: now)))
            .monospacedDigit()
            .onReceive(ticker) { now = $0 }
    }
}

/// The input meter's clock (M16-T5). Polls rather than subscribes: a per-buffer publish is what
/// M6-T10 forbids, and the poll only writes state when the bar count changes — so a silent room
/// costs no redraws at all.
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
    let levelBars: Int?

    @State private var phase: Double = 0

    private let ticker = Timer.publish(
        every: cycle / framesPerCycle, tolerance: 0.05, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        Image(nsImage: StatusIconImage.recordingImage(
            fadedTo: StatusIconImage.pulseAlpha(atPhase: phase), isReplayArmed: isReplayArmed,
            levelBars: levelBars))
            .accessibilityLabel(label)
            .onReceive(ticker) { _ in
                phase = (phase + 1 / Self.framesPerCycle).truncatingRemainder(dividingBy: 1)
            }
    }
}
