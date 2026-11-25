import AppKit
import Carbon.HIToolbox

/// What a key press asks of a player window (docs/06 "Trim window", "Preview window").
enum PlaybackCommand: Equatable {
    case togglePlayback
    case stepFrames(Int)
    case nudgeSeconds(Double)
    case close

    /// Whether holding the key down repeats it. Travelling does; a held space must not flutter
    /// between play and pause.
    var repeats: Bool {
        switch self {
        case .stepFrames, .nudgeSeconds: true
        case .togglePlayback, .close: false
        }
    }
}

/// Which keys a player window claims. The arrows are both windows'; space and Esc are the
/// preview's alone — Trim has buttons a space could be meant for (M37-T3) and a range to lose.
struct PlaybackKeys: Equatable {
    private let claimsSpaceAndEscape: Bool

    static let trim = PlaybackKeys(claimsSpaceAndEscape: false)
    static let preview = PlaybackKeys(claimsSpaceAndEscape: true)

    /// Nil for a key the window leaves to its first responder.
    func command(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> PlaybackCommand? {
        let stepsASecond = modifiers.contains(.shift)
        let isBare = modifiers.intersection([.command, .control, .option, .shift]).isEmpty
        switch keyCode {
        case kVK_LeftArrow: return stepsASecond ? .nudgeSeconds(-1) : .stepFrames(-1)
        case kVK_RightArrow: return stepsASecond ? .nudgeSeconds(1) : .stepFrames(1)
        case kVK_Space where claimsSpaceAndEscape && isBare: return .togglePlayback
        case kVK_Escape where claimsSpaceAndEscape && isBare: return .close
        default: return nil
        }
    }
}

/// Claims a player window's keys ahead of its first responder, `AVPlayerView`, which would
/// scrub ~0.5 s per arrow and toggle on space itself (docs/07). A bare key is no key equivalent.
@MainActor
enum PlaybackKeyMonitor {

    /// `isTarget` scopes the claim to one window, so Settings and the alerts keep their keys.
    static func install(
        _ keys: PlaybackKeys, for isTarget: @escaping (NSWindow) -> Bool,
        perform: @escaping (PlaybackCommand) -> Void
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, isTarget(window),
                  let command = keys.command(
                    keyCode: Int(event.keyCode), modifiers: event.modifierFlags)
            else { return event }
            // A repeat that isn't acted on is still claimed, or the player would act on it.
            if !event.isARepeat || command.repeats { perform(command) }
            return nil
        }
    }

    static func remove(_ monitor: Any?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
