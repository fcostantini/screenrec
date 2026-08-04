import AppKit
import Testing

@testable import AppCore
@testable import AppShell

/// The status item's timing rules and the row geometry — the decisions M28 got wrong (M29-T3).
/// Both defects it shipped are re-introducible here, which is the point.
@Suite struct StatusItemPolicyTests {

    // MARK: - Observation

    @Test func aSecondOpenDoesNotStackASecondRegistration() {
        // The M28 defect: tracking is one-shot and its value is nil almost always, so nothing fired
        // to clear the old registration and every menu open left another armed.
        #expect(StatusItemPolicy.registersObservation(menuIsOpen: true, alreadyObserving: false))
        #expect(!StatusItemPolicy.registersObservation(menuIsOpen: true, alreadyObserving: true))
    }

    @Test func aClosedMenuNeverRegisters() {
        #expect(!StatusItemPolicy.registersObservation(menuIsOpen: false, alreadyObserving: false))
        #expect(!StatusItemPolicy.registersObservation(menuIsOpen: false, alreadyObserving: true))
    }

    // MARK: - The pulse

    @Test func onlyARecordingBreathes() {
        #expect(StatusItemPolicy.pulses(icon: .recording, reduceMotion: false))
        #expect(!StatusItemPolicy.pulses(icon: .idle, reduceMotion: false))
        #expect(!StatusItemPolicy.pulses(icon: .paused, reduceMotion: false))
    }

    @Test func reduceMotionStopsThePulseWithoutStoppingTheRecording() {
        // docs/06: a static red icon, not a missing one.
        #expect(!StatusItemPolicy.pulses(icon: .recording, reduceMotion: true))
    }

    // MARK: - The clock tick

    @Test func theClockTickRedrawsOnlyWhenNothingElseIs() {
        #expect(StatusItemPolicy.redrawsOnClockTick(isPulsing: false, hasClock: true))
        // The pulse already redraws six times a second; a second tick is wasted work.
        #expect(!StatusItemPolicy.redrawsOnClockTick(isPulsing: true, hasClock: true))
        // A still icon with no clock has nothing to advance — this is the idle case, all day.
        #expect(!StatusItemPolicy.redrawsOnClockTick(isPulsing: false, hasClock: false))
    }

    // MARK: - Row geometry

    @MainActor
    @Test func aRowIsWideEnoughForItsTitleAndItsFurniture() {
        let narrow = RecentRowView.width(forTitleWidth: 100)
        let wide = RecentRowView.width(forTitleWidth: 300)
        #expect(wide - narrow == 200)                       // the title's own width, one for one

        // What is left once the title and the well are taken: the insets either side, and room
        // after the text for the chevron. Without that room the chevron draws over the title.
        let furniture = narrow - 100 - RecentRowView.thumbnailSize.width
        #expect(furniture >= 40)
    }

    @MainActor
    @Test func aFrameFitsTheWellWithoutBeingStretched() {
        let well = NSRect(x: 21, y: 3, width: 36, height: 22)

        // This display captures at 4112 × 2570 — 1.600 against the well's 1.636, so it is *height*
        // that binds and the real screen recording does not fill the well's width.
        let screen = RecentRowView.aspectFitted(NSSize(width: 4112, height: 2570), in: well)
        #expect(abs(screen.height - 22) < 0.001)
        #expect(abs(screen.width - 22 * 4112 / 2570) < 0.001)
        #expect(abs(screen.midX - well.midX) < 0.001)
        #expect(abs(screen.midY - well.midY) < 0.001)

        // A wider-than-the-well region binds on width instead…
        let wide = RecentRowView.aspectFitted(NSSize(width: 2000, height: 1000), in: well)
        #expect(abs(wide.width - 36) < 0.001)
        #expect(abs(wide.height - 18) < 0.001)

        // …and a tall one on height, without ever being stretched to fill.
        let tall = RecentRowView.aspectFitted(NSSize(width: 400, height: 1000), in: well)
        #expect(abs(tall.height - 22) < 0.001)
        #expect(tall.width < 36)
    }

    // MARK: - Two measured facts, pinned against silent removal
    //
    // ⚠️ These assert that a flag is set, which cannot prove the chevrons line up or that the blue
    // matches. Both values came from measuring against an AppKit-drawn row (the selection material
    // to delta (0,0,0)); the screenshot remains the instrument for how it looks.

    @MainActor
    @Test func aRowStretchesToTheMenuSoItsChevronSitsAtTheEdge() {
        // Without this the view keeps its created width and the chevron tracks the title length.
        let row = RecentRowView(url: URL(fileURLWithPath: "/tmp/a.mov"), title: "a.mov", thumbnail: nil)
        #expect(row.autoresizingMask.contains(.width))
    }

    @MainActor
    @Test func theHighlightIsTheMenusOwnMaterialRatherThanAFill() {
        // `selectedContentBackgroundColor` is the table blue and measured visibly different.
        let row = RecentRowView(url: URL(fileURLWithPath: "/tmp/a.mov"), title: "a.mov", thumbnail: nil)
        let selection = row.subviews.compactMap { $0 as? NSVisualEffectView }.first
        #expect(selection?.material == .selection)
        #expect(selection?.isEmphasized == true)
    }
}
