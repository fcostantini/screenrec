import AppKit
import Carbon.HIToolbox
import Testing

@testable import AppShell

/// Which keys the Trim and Preview windows claim, and what each asks for (M43-T1).
@Suite struct PlaybackKeysTests {

    /// What AppKit sets on every arrow press, and Caps Lock while it is on.
    private let arrowNoise: NSEvent.ModifierFlags = [.numericPad, .function, .capsLock]

    @Test func theArrowsStepAFrameInBothWindows() {
        for keys in [PlaybackKeys.trim, .preview] {
            #expect(keys.command(keyCode: kVK_LeftArrow, modifiers: arrowNoise) == .stepFrames(-1))
            #expect(keys.command(keyCode: kVK_RightArrow, modifiers: arrowNoise) == .stepFrames(1))
        }
    }

    @Test func shiftMakesItASecondInBothWindows() {
        let shifted = arrowNoise.union(.shift)
        for keys in [PlaybackKeys.trim, .preview] {
            #expect(keys.command(keyCode: kVK_LeftArrow, modifiers: shifted) == .nudgeSeconds(-1))
            #expect(keys.command(keyCode: kVK_RightArrow, modifiers: shifted) == .nudgeSeconds(1))
        }
    }

    @Test func spacePlaysAndPausesThePreview() {
        #expect(PlaybackKeys.preview.command(keyCode: kVK_Space, modifiers: []) == .togglePlayback)
        #expect(
            PlaybackKeys.preview.command(keyCode: kVK_Space, modifiers: .capsLock)
                == .togglePlayback)
    }

    @Test func escapeClosesThePreview() {
        #expect(PlaybackKeys.preview.command(keyCode: kVK_Escape, modifiers: []) == .close)
    }

    /// M37-T3: Trim has buttons a space could be meant for, and a range Esc would throw away.
    @Test func trimLeavesSpaceAndEscapeToItsFirstResponder() {
        #expect(PlaybackKeys.trim.command(keyCode: kVK_Space, modifiers: []) == nil)
        #expect(PlaybackKeys.trim.command(keyCode: kVK_Escape, modifiers: []) == nil)
    }

    @Test func aModifiedSpaceOrEscapeIsLeftAlone() {
        for modifier in [NSEvent.ModifierFlags.command, .control, .option, .shift] {
            #expect(PlaybackKeys.preview.command(keyCode: kVK_Space, modifiers: modifier) == nil)
            #expect(PlaybackKeys.preview.command(keyCode: kVK_Escape, modifiers: modifier) == nil)
        }
    }

    @Test func everyOtherKeyIsLeftAlone() {
        for key in [kVK_ANSI_I, kVK_ANSI_O, kVK_Return, kVK_UpArrow, kVK_DownArrow, kVK_Tab] {
            #expect(PlaybackKeys.preview.command(keyCode: key, modifiers: []) == nil)
            #expect(PlaybackKeys.trim.command(keyCode: key, modifiers: []) == nil)
        }
    }

    /// A held arrow travels; a held space must not flutter between play and pause.
    @Test func onlyTravellingRepeatsWhileTheKeyIsHeld() {
        #expect(PlaybackCommand.stepFrames(1).repeats)
        #expect(PlaybackCommand.nudgeSeconds(-1).repeats)
        #expect(!PlaybackCommand.togglePlayback.repeats)
        #expect(!PlaybackCommand.close.repeats)
    }
}
