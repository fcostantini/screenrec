import Foundation
import Testing

@testable import AppCore

/// Whether banners will render while capturing, and what the app is allowed to claim about it
/// (M35-T1, ADR-022). The setting has no public API, so this reads a private domain — which is why
/// **every** failure path has to land on `.unknown` rather than on a guess.
@Suite struct BannerVisibilityTests {

    private func preferences(_ entries: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
    }

    // MARK: - The mapping

    /// The stored flag is the inverse of the toggle the user sees — established by flipping it
    /// (docs/07), not from its name. An inverted mapping would tell everyone the opposite of the truth.
    @Test func theStoredFlagIsTheInverseOfWhatTheUserSees() throws {
        #expect(BannerVisibility.decoded(from: try preferences(["dndMirrored": true])) == .hidden)
        #expect(BannerVisibility.decoded(from: try preferences(["dndMirrored": false])) == .shown)
    }

    @Test func everyUnreadableShapeIsUnknownRatherThanAGuess() throws {
        // The domain isn't there at all.
        #expect(BannerVisibility.decoded(from: nil) == .unknown)
        // Present, but not a property list.
        #expect(BannerVisibility.decoded(from: Data("not a plist".utf8)) == .unknown)
        // A plist whose key is gone — the shape a macOS release would leave behind.
        #expect(BannerVisibility.decoded(from: try preferences(["dndDisplaySleep": true])) == .unknown)
        // The key is there but no longer a boolean.
        #expect(BannerVisibility.decoded(from: try preferences(["dndMirrored": "yes"])) == .unknown)
    }

    @Test func onlyAWorkingSetupIsSpareTheWarning() {
        #expect(BannerVisibility.shown.warrantsWarning == false)
        #expect(BannerVisibility.hidden.warrantsWarning)
        #expect(BannerVisibility.unknown.warrantsWarning)   // can't tell ⇒ still say something
    }

    // MARK: - The once-ever flag

    /// 🔴 The reason the decision lives in AppCore: the flag is spent here, before the alert is shown.
    /// Warning someone whose banners work would burn their one warning on nothing — and leave them
    /// unwarned if they later turned the setting off.
    @MainActor
    @Test func anArmWithNothingToWarnAboutSpendsNothing() {
        let state = AppState(defaults: TestDefaults.make())
        var fired: [BannerVisibility] = []
        state.bannerVisibility = { .shown }
        state.onReplayBannerWarning = { fired.append($0) }

        state.isReplayArmed = true

        #expect(fired.isEmpty, "a user whose banners work must not be warned")
        #expect(!state.hasSeenReplayBannerWarning, "the one-time flag must survive for when it matters")
    }

    @MainActor
    @Test func aSuppressedArmWarnsOnceAndCarriesItsState() {
        let state = AppState(defaults: TestDefaults.make())
        var fired: [BannerVisibility] = []
        state.bannerVisibility = { .hidden }
        state.onReplayBannerWarning = { fired.append($0) }

        state.isReplayArmed = true
        #expect(fired == [.hidden])          // the alert is told what it is warning about
        #expect(state.hasSeenReplayBannerWarning)

        state.isReplayArmed = false
        state.isReplayArmed = true
        #expect(fired == [.hidden], "once ever, not once per arm")
    }

    /// A failed read must still warn — it is the case the original copy was written for.
    @MainActor
    @Test func anUnreadableSettingStillWarns() {
        let state = AppState(defaults: TestDefaults.make())
        var fired: [BannerVisibility] = []
        state.bannerVisibility = { .unknown }
        state.onReplayBannerWarning = { fired.append($0) }

        state.isReplayArmed = true
        #expect(fired == [.unknown])
        #expect(state.hasSeenReplayBannerWarning)
    }

    /// The flag turning true must not un-warn someone who was never warned: a `.shown` arm leaves the
    /// flag alone, so the arm *after* the setting is turned off still gets the alert.
    @MainActor
    @Test func turningTheSettingOffLaterStillEarnsTheWarning() {
        let state = AppState(defaults: TestDefaults.make())
        var fired: [BannerVisibility] = []
        let suppressed = Box<Bool>()
        suppressed.value = false
        state.bannerVisibility = { suppressed.value == true ? .hidden : .shown }
        state.onReplayBannerWarning = { fired.append($0) }

        state.isReplayArmed = true           // banners fine — no warning, flag unspent
        state.isReplayArmed = false
        #expect(fired.isEmpty)

        suppressed.value = true              // the user turns the setting off
        state.isReplayArmed = true
        #expect(fired == [.hidden], "the first arm that actually warrants a warning gets one")
    }
}
