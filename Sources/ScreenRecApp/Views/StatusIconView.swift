import AppCore
import AppKit
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

    static func image(for icon: StatusIcon, isReplayArmed: Bool = false) -> NSImage {
        switch (icon, isReplayArmed) {
        case (.idle, false): idleImage
        case (.recording, false): recordingImage
        case (.paused, false): pausedImage
        case (.idle, true): idleArmedImage
        case (.recording, true): recordingArmedImage
        case (.paused, true): pausedArmedImage
        }
    }

    /// The recording icon faded for the pulse; `alpha` comes from `pulseAlpha(atPhase:)`.
    /// The armed badge does not fade — armed is a steady state, only recording breathes.
    static func recordingImage(fadedTo alpha: Double, isReplayArmed: Bool = false) -> NSImage {
        let base = recordingImage
        guard alpha < 1 else { return isReplayArmed ? recordingArmedImage : base }
        // `NSImage(size:flipped:)` re-renders per representation, so the fade survives a scale
        // change between Retina and non-Retina displays.
        let faded = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            if isReplayArmed { drawBadge(in: rect, onTemplate: false) }
            return true
        }
        faded.isTemplate = base.isTemplate
        return faded
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

/// The status item's label. Pulses while recording, unless the user asked for less motion.
struct StatusIconView: View {
    let icon: StatusIcon
    var isReplayArmed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if icon == .recording && !reduceMotion {
            PulsingRecordingIcon(
                label: StatusIconImage.label(for: icon, isReplayArmed: isReplayArmed),
                isReplayArmed: isReplayArmed)
        } else {
            Image(nsImage: StatusIconImage.image(for: icon, isReplayArmed: isReplayArmed))
                .accessibilityLabel(StatusIconImage.label(for: icon, isReplayArmed: isReplayArmed))
        }
    }
}

/// Redraws the recording icon frame by frame, alive only while recording: SwiftUI's implicit
/// animations don't drive a `MenuBarExtra` label, so the pulse must be timer-driven.
private struct PulsingRecordingIcon: View {
    /// Slow enough to read as breathing rather than as an alert.
    private static let cycle: TimeInterval = 2
    private static let framesPerCycle: Double = 12

    let label: String
    let isReplayArmed: Bool

    @State private var phase: Double = 0

    private let ticker = Timer.publish(
        every: cycle / framesPerCycle, tolerance: 0.05, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        Image(nsImage: StatusIconImage.recordingImage(
            fadedTo: StatusIconImage.pulseAlpha(atPhase: phase), isReplayArmed: isReplayArmed))
            .accessibilityLabel(label)
            .onReceive(ticker) { _ in
                phase = (phase + 1 / Self.framesPerCycle).truncatingRemainder(dividingBy: 1)
            }
    }
}
