import AppCore
import AppKit
import SwiftUI

/// Draws the status item (docs/06 "Status item").
///
/// Colour is baked into an `NSImage` here rather than applied with SwiftUI's `foregroundStyle`
/// because the menu bar tints *template* images to match itself: left as templates, the red and
/// amber that carry the whole meaning would come out the same monochrome as idle.
@MainActor
enum StatusIconImage {

    /// Alpha floor of the recording pulse. It dips, never disappears — a status item that
    /// blinks fully out reads as a glitch, and for a moment says "not recording".
    private static let pulseFloor: Double = 0.45

    /// The status item's accessible name. It lives here rather than on the images because an
    /// `NSImage`'s `accessibilityDescription` does not reach the accessibility tree through
    /// `Image(nsImage:)`, and a label-based `MenuBarExtra` has no title to fall back on — so
    /// the view must apply this explicitly or the item is announced as an unnamed image.
    static func label(for icon: StatusIcon) -> String {
        switch icon {
        case .idle: "ScreenRec: ready"
        case .recording: "ScreenRec: recording"
        case .paused: "ScreenRec: paused"
        }
    }

    // Built once each. The symbol lookup and palette render are constant, and the pulse would
    // otherwise redo both several times a second for the length of a recording.
    private static let idleImage = template("record.circle")
    private static let recordingImage = tinted("record.circle.fill", .systemRed)
    private static let pausedImage = tinted("circle.lefthalf.filled", .systemOrange)

    static func image(for icon: StatusIcon) -> NSImage {
        switch icon {
        case .idle: idleImage
        case .recording: recordingImage
        case .paused: pausedImage
        }
    }

    /// The recording icon faded for the pulse; `alpha` comes from `pulseAlpha(atPhase:)`.
    static func recordingImage(fadedTo alpha: Double) -> NSImage {
        let base = recordingImage
        guard alpha < 1 else { return base }
        // `NSImage(size:flipped:)` re-renders per representation, so the fade survives a scale
        // change (dragging the window between Retina and non-Retina displays).
        let faded = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
        faded.isTemplate = base.isTemplate
        return faded
    }

    /// Maps the pulse's phase in [0,1) to an alpha: a raised cosine, so it eases at both ends
    /// instead of stepping — "subtle pulse", not a blink.
    static func pulseAlpha(atPhase phase: Double) -> Double {
        let eased = (1 + cos(2 * .pi * phase)) / 2      // 1 → 0 → 1 over the cycle
        return pulseFloor + (1 - pulseFloor) * eased
    }

    /// Idle is the one state left as a template: it should look like every other menu-bar icon,
    /// which means letting the system tint it for light/dark and for menu-bar highlight.
    private static func template(_ name: String) -> NSImage {
        // Invariant: every name passed here is a compile-time constant present in macOS 15 —
        // the deployment target (LSMinimumSystemVersion) — so the lookup cannot fail. The
        // description is nil deliberately; see `label(for:)`.
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }

    private static func tinted(_ name: String, _ color: NSColor) -> NSImage {
        let base = template(name)
        // Degrade rather than trap: a symbol that won't take a palette configuration costs us
        // the colour, which is cosmetic. Trapping would take down the recording the icon exists
        // to report on — and this runs on the ordinary start/pause path, not a preflight.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if icon == .recording && !reduceMotion {
            PulsingRecordingIcon(label: StatusIconImage.label(for: icon))
        } else {
            Image(nsImage: StatusIconImage.image(for: icon))
                .accessibilityLabel(StatusIconImage.label(for: icon))
        }
    }
}

/// Redraws the recording icon frame by frame, alive only while recording: SwiftUI's implicit
/// animations don't drive a status item — the label is rendered to an `NSImage` — so the pulse
/// has to be hand-driven rather than declared.
private struct PulsingRecordingIcon: View {
    /// Slow enough to read as breathing rather than as an alert.
    private static let cycle: TimeInterval = 2
    private static let framesPerCycle: Double = 12

    let label: String

    @State private var phase: Double = 0

    private let ticker = Timer.publish(
        every: cycle / framesPerCycle, tolerance: 0.05, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        Image(nsImage: StatusIconImage.recordingImage(
            fadedTo: StatusIconImage.pulseAlpha(atPhase: phase)))
            .accessibilityLabel(label)
            .onReceive(ticker) { _ in
                phase = (phase + 1 / Self.framesPerCycle).truncatingRemainder(dividingBy: 1)
            }
    }
}
