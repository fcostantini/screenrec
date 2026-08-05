import Foundation
import RecorderCore
import Testing

@testable import AppCore

/// The update check's decision (M32-T2, ADR-020). Pure, because the live half can only ever be
/// smoke-tested — and because every one of these cases is a way the app could tell a user something
/// false about their own build.
@Suite struct UpdateCheckTests {

    // MARK: - Parsing a tag

    /// The repo's tags carry a `v`; `VERSION` does not. Both have to parse to the same thing, or a
    /// build compares itself against a stranger.
    @Test func aLeadingVIsOptional() {
        #expect(UpdateCheck.components("v1.16.0") == [1, 16, 0])
        #expect(UpdateCheck.components("1.16.0") == [1, 16, 0])
    }

    /// Ignored, never guessed at: ordering a tag we don't understand is how a build talks itself
    /// into "you're out of date" against something that was never a release.
    @Test func anythingThatIsNotThreeIntegersIsIgnored() {
        for tag in ["1.16", "1.16.0.1", "v1.16.0-beta", "nightly", "", "v", "1.x.0", "-1.0.0"] {
            #expect(UpdateCheck.components(tag) == nil, "\(tag) should not parse")
        }
    }

    // MARK: - Choosing the newest

    @Test func findsTheNewestReleaseThatIsActuallyNewer() {
        let tags = ["v1.15.0", "v1.16.0", "v1.15.1", "v1.14.0"]
        #expect(UpdateCheck.newestRelease(among: tags, laterThan: "1.15.0") == "v1.16.0")
    }

    /// Ordering is per component, not lexicographic — `1.9.0` vs `1.10.0` is where a string compare
    /// gets it backwards.
    @Test func ordersByNumberRatherThanText() {
        #expect(UpdateCheck.newestRelease(among: ["v1.10.0"], laterThan: "1.9.0") == "v1.10.0")
        #expect(UpdateCheck.newestRelease(among: ["v1.9.0"], laterThan: "1.10.0") == nil)
        #expect(UpdateCheck.newestRelease(among: ["v2.0.0"], laterThan: "1.99.99") == "v2.0.0")
    }

    /// The common case, and it must say nothing at all.
    @Test func theCurrentVersionIsNotAnUpdate() {
        #expect(UpdateCheck.newestRelease(among: ["v1.16.0"], laterThan: "1.16.0") == nil)
    }

    /// A local build ahead of anything published — never tell it to downgrade.
    @Test func aBuildAheadOfEveryReleaseIsNotBehind() {
        #expect(UpdateCheck.newestRelease(among: ["v1.16.0", "v1.15.1"], laterThan: "1.17.0") == nil)
    }

    /// Every failing shape lands on the same silence: ADR-020's "silent when it fails".
    @Test func nothingUsableMeansNothingIsSaid() {
        #expect(UpdateCheck.newestRelease(among: [], laterThan: "1.16.0") == nil)
        #expect(UpdateCheck.newestRelease(among: ["nightly", "v1.x"], laterThan: "1.16.0") == nil)
        // An unparseable *own* version: saying nothing beats saying something wrong.
        #expect(UpdateCheck.newestRelease(among: ["v9.9.9"], laterThan: "dev") == nil)
    }

    /// Unparseable tags must not hide a real one sitting beside them.
    @Test func oneBadTagDoesNotSuppressAGoodOne() {
        #expect(
            UpdateCheck.newestRelease(among: ["nightly", "v1.17.0", "v1.x.y"], laterThan: "1.16.0")
                == "v1.17.0")
    }

    // MARK: - What reaches the app

    @MainActor
    @Test func aNewerReleaseReachesTheStateAndAnOlderOneLeavesItAlone() async {
        let state = AppState(defaults: TestDefaults.make())
        #expect(state.availableUpdate == nil)

        await state.checkForUpdate { ["v99.0.0"] }
        #expect(state.availableUpdate == "v99.0.0")

        // Back to current — the row must disappear again rather than latch on.
        await state.checkForUpdate { ["v0.0.1"] }
        #expect(state.availableUpdate == nil)
    }

    /// Offline, rate-limited, or refused — all the same outcome, and never an error surface.
    @MainActor
    @Test func aFailedCheckIsIndistinguishableFromBeingCurrent() async {
        let state = AppState(defaults: TestDefaults.make())
        await state.checkForUpdate { [] }
        #expect(state.availableUpdate == nil)
    }

    // MARK: - The live half (opt-in)

    /// The one part no unit test can cover: that the endpoint answers, the shape decodes, and the
    /// verdict against this build is what it should be. Gated like the encode suites, so the default
    /// run stays offline and deterministic — a test that needs the network is a test that fails on a
    /// train.
    ///
    /// `SCREENREC_LIVE_UPDATE_CHECK=1 swift test --filter UpdateCheckTests`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_LIVE_UPDATE_CHECK"] == "1"))
    func theRealReleaseListAnswersAndTheVerdictIsRight() async {
        let tags = await UpdateCheck.fetchTags()
        #expect(!tags.isEmpty, "the releases endpoint returned nothing")

        // This build is the newest release, so it must be told nothing at all.
        #expect(UpdateCheck.newestRelease(among: tags, laterThan: CoreInfo.version) == nil)

        // …and the case the milestone exists for: someone still on an old build IS told.
        let old = UpdateCheck.newestRelease(among: tags, laterThan: "1.7.0")
        #expect(old != nil, "a recipient on 1.7.0 should be offered something newer")
        // Printed, not `Issue.record`: a diagnostic must not turn a passing test red.
        print("LIVE: \(tags.count) tags; this build \(CoreInfo.version); a 1.7.0 build sees \(old ?? "nothing")")
    }

    // MARK: - The row, and the off switch (M32-T3)

    @Test func theRowNamesTheVersionWithoutTheTagsV() {
        #expect(MenuHeader.updateAvailable("v1.17.0") == "1.17.0 is available")
        #expect(MenuHeader.updateAvailable("1.17.0") == "1.17.0 is available")
    }

    /// The common case shows no row at all — the surface exists only when there is news.
    @Test func nothingToSayMeansNoRow() {
        #expect(MenuHeader.updateAvailable(nil) == nil)
        #expect(MenuHeader.updateAvailable("") == nil)
    }

    /// Off must mean **no request**, not a request whose answer is thrown away — the whole point of
    /// the switch is that the app then makes no network requests at all (ADR-020's privacy cost).
    @MainActor
    @Test func turningTheCheckOffMakesNoRequestAtAll() async {
        let state = AppState(defaults: TestDefaults.make())
        let asked = Flag()
        state.checksForUpdates = false

        await state.checkForUpdate { asked.raise(); return ["v99.0.0"] }
        #expect(!asked.isRaised, "a disabled check must not reach the network")
        #expect(state.availableUpdate == nil)
    }

    /// And turning it off clears a row that was already showing, rather than leaving it stranded.
    @MainActor
    @Test func turningItOffAlsoClearsARowAlreadyShowing() async {
        let state = AppState(defaults: TestDefaults.make())
        await state.checkForUpdate { ["v99.0.0"] }
        #expect(state.availableUpdate == "v99.0.0")

        state.checksForUpdates = false
        await state.checkForUpdate { ["v99.0.0"] }
        #expect(state.availableUpdate == nil)
    }
}
