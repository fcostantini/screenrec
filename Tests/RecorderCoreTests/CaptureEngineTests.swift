import ScreenCaptureKit
import Foundation
import Testing
@testable import RecorderCore

@Suite struct CaptureEngineTests {

    // The start gate, with injected permission state + display count (the denied-path
    // unit test — live TCC revocation would destroy this terminal's own grant, docs/02 §2).

    @Test func failsWhenScreenExplicitlyDenied() {
        guard case .fail = CaptureEngine.startDecision(
            screenPermission: .denied, availableDisplays: 1,
            content: .display(.main), runningBundleIDs: []) else {
            Issue.record("expected .fail when screen recording is denied")
            return
        }
    }

    @Test func neverBlamesPermissionForZeroDisplays() {
        // Zero displays cannot mean "ungranted": an ungranted process THROWS from
        // SCShareableContent (02 §10) instead of enumerating zero, so getting here at all means
        // we are authorized. The only measured zero-display state is locked+slept (02 §7).
        // Both live preflight values must say so — `.notDetermined` especially, since that is
        // what a freshly-built CLI binary reports even when it captures fine (02 §10), and it
        // is the only cell the CLI can reach.
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 0,
            content: .display(.main), runningBundleIDs: [])
            == .fail(CaptureEngine.noDisplaysGuidance))
        #expect(CaptureEngine.startDecision(
            screenPermission: .notDetermined, availableDisplays: 0,
            content: .display(.main), runningBundleIDs: [])
            == .fail(CaptureEngine.noDisplaysGuidance))
    }

    @Test func deniedBeatsDisplaysPresent() {
        // Displays present, but the grant is explicitly refused — permission still wins.
        // (Defensive: Permissions.screenRecordingState() cannot currently produce `.denied`.)
        #expect(CaptureEngine.startDecision(
            screenPermission: .denied, availableDisplays: 2,
            content: .display(.main), runningBundleIDs: [])
            == .fail(CaptureEngine.permissionGuidance))
    }

    @Test func proceedsWhenGrantedWithDisplays() {
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 2,
            content: .display(.main), runningBundleIDs: []) == .proceed)
    }

    @Test func proceedsWhenNotDeterminedButDisplaysPresent() {
        // CGPreflight is unreliable for CLI binaries; visible displays mean we can capture.
        #expect(CaptureEngine.startDecision(
            screenPermission: .notDetermined, availableDisplays: 1,
            content: .display(.main), runningBundleIDs: []) == .proceed)
    }

    // Start-error → user-facing message (the thrown-permission path, docs/02 §2/§10).

    @Test func startErrorMapsSCKDeclineToGuidance() {
        let declined = NSError(domain: SCStreamError.errorDomain, code: -3801)
        #expect(CaptureEngine.startErrorMessage(declined) == CaptureEngine.permissionGuidance)
    }

    @Test func startErrorMapsLostDisplayToNoDisplaysGuidance() {
        // The display can vanish inside the start window too — enumeration succeeds, then
        // startCapture throws -3815. Same condition as the other two surfaces, same wording.
        let lost = NSError(domain: SCStreamError.errorDomain, code: -3815)
        #expect(CaptureEngine.startErrorMessage(lost) == CaptureEngine.noDisplaysGuidance)
    }

    @Test func startErrorMapsDeclineMessageToGuidance() {
        let declined = NSError(domain: "Other", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The user declined TCCs for display capture"])
        #expect(CaptureEngine.startErrorMessage(declined) == CaptureEngine.permissionGuidance)
    }

    @Test func startErrorPassesThroughOtherErrors() {
        let other = NSError(domain: "Foo", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk on fire"])
        #expect(CaptureEngine.startErrorMessage(other) == "disk on fire")
    }

    // Stream death → EndReason (docs/01). -3815 was measured, not guessed: `pmset
    // displaysleepnow` mid-recording (02 §7). Lid-close and unplug are still unobserved.

    @Test func streamErrorMapsLostDisplayToDisplayDisconnected() {
        let lost = NSError(domain: SCStreamError.errorDomain, code: -3815)  // measured
        #expect(CaptureEngine.endReason(forStreamError: lost, content: .display(.main)) == .displayDisconnected)
        let noList = NSError(domain: SCStreamError.errorDomain, code: -3814)  // by kinship
        #expect(CaptureEngine.endReason(forStreamError: noList, content: .display(.main)) == .displayDisconnected)
    }

    @Test func streamErrorMapsSystemIndicatorStopToUserStopped() {
        // macOS's screen-recording indicator lets the user stop the capture; SCK reports that
        // as -3817. Anything but `.userStopped` makes ADR-007 read the most ordinary stop there
        // is as a fail-stop, and M4 would fire an "ended unexpectedly" notification for it.
        let stopped = NSError(domain: SCStreamError.errorDomain, code: -3817)
        #expect(CaptureEngine.endReason(forStreamError: stopped, content: .display(.main)) == .userStopped)
    }

    @Test func streamErrorKeepsTheCodeForUnmappedSCKErrors() {
        // SCK errors are opaque (02 §2); carrying the code is how -3815 was identified at all.
        let unknown = NSError(domain: SCStreamError.errorDomain, code: -3811,
            userInfo: [NSLocalizedDescriptionKey: "internal error"])
        #expect(CaptureEngine.endReason(forStreamError: unknown, content: .display(.main))
            == .streamError("internal error [SCStreamError -3811]"))
    }

    @Test func streamErrorPassesThroughNonSCKErrors() {
        let other = NSError(domain: "Foo", code: 7, userInfo: [NSLocalizedDescriptionKey: "kaboom"])
        #expect(CaptureEngine.endReason(forStreamError: other, content: .display(.main)) == .streamError("kaboom"))
    }

    // MARK: per-app content (M7-T1)

    @Test func appContentResolvesAgainstRunningApps() {
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 1,
            content: .app(bundleID: "com.example.app"),
            runningBundleIDs: ["com.other", "com.example.app"]) == .proceed)
    }

    @Test func missingAppFailsWithActionableCopy() {
        let decision = CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 1,
            content: .app(bundleID: "com.example.gone"), runningBundleIDs: ["com.other"])
        // Says what happened AND what to do (M6-T3 bar), and names the app.
        guard case .fail(let message) = decision else {
            Issue.record("expected .fail for an unlisted app")
            return
        }
        #expect(message.contains("com.example.gone"))
        #expect(message.contains("Open the app"))
    }

    @Test func stallWatchdogOnlyAttachesForDisplayContent() {
        // Its "user active ⇒ frames expected" premise fails under an app filter (docs/02 §7);
        // a region is a display-filter capture, so it inherits the display path's watchdog.
        #expect(CaptureEngine.attachesStallWatchdog(to: .display(.main)))
        #expect(CaptureEngine.attachesStallWatchdog(to: .display(.id(7))))
        #expect(!CaptureEngine.attachesStallWatchdog(to: .app(bundleID: "com.example.app")))
        #expect(CaptureEngine.attachesStallWatchdog(
            to: .region(display: .main, rect: CGRect(x: 0, y: 0, width: 100, height: 100))))
    }

    // MARK: region content (M11-T1) — the pure resolveRegion decision (docs/02 §1b).
    // Fixture display: 2056×1285 pt @2× (the dev machine), so pt×2 = px.

    private static let displayPoints = CGSize(width: 2056, height: 1285)

    @Test func regionFullyInsideResolvesToEvenPixels() {
        let decision = CaptureEngine.resolveRegion(
            rect: CGRect(x: 40, y: 60, width: 800, height: 500),
            displayPointSize: Self.displayPoints, scale: 2)
        #expect(decision == .ok(CaptureEngine.RegionRender(
            sourceRect: CGRect(x: 40, y: 60, width: 800, height: 500),
            width: 1600, height: 1000)))
    }

    @Test func regionStraddlingEdgeClampsToDisplay() {
        // 1800 + 800 = 2600 pt overruns the 2056-pt display: the width clamps to 256 pt.
        let decision = CaptureEngine.resolveRegion(
            rect: CGRect(x: 1800, y: 60, width: 800, height: 500),
            displayPointSize: Self.displayPoints, scale: 2)
        #expect(decision == .ok(CaptureEngine.RegionRender(
            sourceRect: CGRect(x: 1800, y: 60, width: 256, height: 500),
            width: 512, height: 1000)))
    }

    @Test func regionSnapsOddPixelsDownToEvenAndTrimsSourceRect() {
        // 400.5 pt × 2 = 801 px (odd) → floors to 800 px, and sourceRect is trimmed to 400.0 pt
        // so the point→pixel map stays exact (no sub-pixel squash).
        guard case .ok(let render) = CaptureEngine.resolveRegion(
            rect: CGRect(x: 40, y: 60, width: 400.5, height: 500),
            displayPointSize: Self.displayPoints, scale: 2) else {
            Issue.record("expected .ok for an in-bounds region")
            return
        }
        #expect(render.width == 800)
        #expect(render.height == 1000)
        #expect(render.sourceRect.width == 400.0)
    }

    @Test func regionFractionalStraddleNeverOverrunsTheEdge() {
        // A fractional edge-straddle must floor its pixels down: `sourceRect` may never push
        // past the display, or SCK crops against a rect it can't honor.
        guard case .ok(let render) = CaptureEngine.resolveRegion(
            rect: CGRect(x: 1800.1, y: 1000.1, width: 800, height: 800),
            displayPointSize: Self.displayPoints, scale: 2) else {
            Issue.record("expected .ok for a rect that overlaps the display")
            return
        }
        #expect(render.sourceRect.maxX <= Self.displayPoints.width)
        #expect(render.sourceRect.maxY <= Self.displayPoints.height)
    }

    @Test func regionFullyOffScreenFailsLoud() {
        let decision = CaptureEngine.resolveRegion(
            rect: CGRect(x: 4000, y: 60, width: 800, height: 500),
            displayPointSize: Self.displayPoints, scale: 2)
        guard case .fail(let message) = decision else {
            Issue.record("expected .fail for an off-screen region")
            return
        }
        // Says what happened AND what to do (M6-T3 bar), and names the offending rect.
        #expect(message.contains("4000"))
        #expect(message.contains("doesn't overlap"))
        #expect(message.contains("on screen"))
    }

    @Test func regionWithZeroAreaFailsLoud() {
        guard case .fail(let message) = CaptureEngine.resolveRegion(
            rect: CGRect(x: 40, y: 60, width: 800, height: 0),
            displayPointSize: Self.displayPoints, scale: 2) else {
            Issue.record("expected .fail for a zero-height region")
            return
        }
        #expect(message.contains("positive width and height"))
    }

    @Test func regionWithNonFiniteDimensionFailsLoud() {
        for rect in [
            CGRect(x: 40, y: 60, width: CGFloat.infinity, height: 500),
            CGRect(x: 40, y: 60, width: 800, height: CGFloat.nan),
        ] {
            guard case .fail = CaptureEngine.resolveRegion(
                rect: rect, displayPointSize: Self.displayPoints, scale: 2) else {
                Issue.record("expected .fail for a non-finite region")
                return
            }
        }
    }

    @Test func regionRoundingBelowTwoPixelsFailsLoud() {
        // On-screen but sub-pixel: 0.2 pt × 2 rounds to 0 px, which no encoder can take.
        guard case .fail(let message) = CaptureEngine.resolveRegion(
            rect: CGRect(x: 40, y: 60, width: 0.2, height: 500),
            displayPointSize: Self.displayPoints, scale: 2) else {
            Issue.record("expected .fail for a sub-pixel region")
            return
        }
        #expect(message.contains("too small"))
    }

    @Test func regionContentSelectionIsEquatable() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(ContentSelection.region(display: .main, rect: rect)
            == .region(display: .main, rect: rect))
        #expect(ContentSelection.region(display: .main, rect: rect)
            != .region(display: .main, rect: CGRect(x: 0, y: 0, width: 20, height: 10)))
    }

    @Test func eachPurposeAssertsItsOwnReason() {
        // The reason is what `pmset -g assertions` shows the user, so an armed stream must never
        // report a recording (ADR-018) — and no two purposes may share a string.
        #expect(CaptureEngine.Purpose.recording.assertionReason == "Recording the screen")
        #expect(CaptureEngine.Purpose.replayBuffer.assertionReason == "Instant replay is armed")
        #expect(CaptureEngine.Purpose.diagnostic.assertionReason == "Capturing the screen")
        let reasons = CaptureEngine.Purpose.allCases.map(\.assertionReason)
        #expect(Set(reasons).count == reasons.count)
    }

    @Test func onlyRegionAndWindowForbidTheDisplayFallback() {
        // A region's rect is tied to one display's geometry, so a missing main display must fail
        // loud, not crop against `displays.first` (M13-T4). Whole-screen/app may fall back. A
        // window resolves no display at all, and a substitute one would not contain it.
        #expect(!CaptureEngine.allowsDisplayFallback(
            for: .region(display: .main, rect: CGRect(x: 0, y: 0, width: 10, height: 10))))
        #expect(!CaptureEngine.allowsDisplayFallback(for: .window(id: 37, ownerBundleID: nil)))
        #expect(CaptureEngine.allowsDisplayFallback(for: .display(.main)))
        #expect(CaptureEngine.allowsDisplayFallback(for: .app(bundleID: "com.example.app")))
    }

    // MARK: window content (M17-T1)

    @Test func windowContentNeedsNoRunningAppMatch() {
        // A window is resolved by id against `content.windows`, not by bundle id — so the
        // pre-flight decision has nothing to check and must not block on the app list.
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 1,
            content: .window(id: 37, ownerBundleID: nil), runningBundleIDs: []) == .proceed)
    }

    @Test func goneWindowCopyNamesTheRelaunchTrap() {
        // A window id is not stable across a relaunch of its app (docs/02 §1c), which is the
        // failure this path mostly sees — the copy has to say so and what to do (M6-T3 bar).
        #expect(CaptureEngine.windowUnavailableMessage.contains("relaunched"))
        #expect(CaptureEngine.windowUnavailableMessage.contains("choose the window again"))
    }

    @Test func aGoneSourceIsReportedAsWhicheverSourceWasBeingCaptured() {
        // Measured both ways (docs/02 §1c): the same code means the display went away under a
        // display filter and the window went away under a window filter. Reporting a closed
        // window as a disconnected display would send the user looking at their monitor cable.
        for code in [-3815, -3814] {
            let gone = NSError(domain: SCStreamError.errorDomain, code: code)
            #expect(CaptureEngine.endReason(forStreamError: gone, content: .window(id: 37, ownerBundleID: nil))
                == .windowClosed)
            #expect(CaptureEngine.endReason(forStreamError: gone, content: .display(.main))
                == .displayDisconnected)
            #expect(CaptureEngine.endReason(forStreamError: gone, content: .app(bundleID: "com.x"))
                == .displayDisconnected)
        }
    }

    @Test func theSystemIndicatorStopIsStillAUserStopUnderAWindowFilter() {
        // The window-aware branch must not swallow the ordinary stop (-3817) — that would turn
        // the most common stop there is into a fail-stop (ADR-007).
        let stopped = NSError(domain: SCStreamError.errorDomain, code: -3817)
        #expect(CaptureEngine.endReason(forStreamError: stopped, content: .window(id: 37, ownerBundleID: nil))
            == .userStopped)
    }

    @Test func aPickIsRefusedWhenTheIdNowBelongsToAnotherApp() {
        // The hazard ruling A1 exists for: window ids are REUSED, so a pick restored from disk can
        // resolve to some other app's window. Binding it would record the wrong thing while looking
        // like it worked — strictly worse than failing.
        #expect(!CaptureEngine.windowOwnerMatches("com.apple.Safari", "com.apple.TextEdit"))
        #expect(CaptureEngine.windowOwnerMatches("com.apple.Safari", "com.apple.Safari"))
        // A window whose owner SCK can't name can't satisfy an expectation either.
        #expect(!CaptureEngine.windowOwnerMatches(nil, "com.apple.Safari"))
        // No expectation ⇒ nothing to check: the CLI lists and binds in one breath.
        #expect(CaptureEngine.windowOwnerMatches("com.apple.Safari", nil))
        #expect(CaptureEngine.windowOwnerMatches(nil, nil))
    }

    @Test func windowContentSkipsTheStallWatchdog() {
        // A window can be minimised or fully occluded while the user works elsewhere, so
        // "user active ⇒ frames expected" fails exactly as it does under an app filter.
        #expect(!CaptureEngine.attachesStallWatchdog(to: .window(id: 37, ownerBundleID: nil)))
    }
}
