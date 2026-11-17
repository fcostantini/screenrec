import Foundation
import Testing
import UploadCore

@testable import AppCore

/// The YouTube account's state machine (M40-T2), with the browser sign-in and the revocation
/// injected — every transition a user can cause, without a browser or a network.
@MainActor
@Suite struct UploadModelTests {

    private let credentials = GoogleClientCredentials(clientID: "id.apps", clientSecret: "s3cret")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func token(endsIn seconds: TimeInterval? = nil) -> GoogleToken {
        GoogleToken(
            accessToken: "at", accessTokenExpiry: now.addingTimeInterval(3599), refreshToken: "rt",
            refreshTokenExpiry: seconds.map(now.addingTimeInterval))
    }

    private func makeModel(
        store: any TokenStore = InMemoryTokenStore(), credentials: GoogleClientCredentials?
    ) -> UploadModel {
        UploadModel(credentials: credentials, store: store, now: now)
    }

    private func makeModel(store: any TokenStore = InMemoryTokenStore()) -> UploadModel {
        makeModel(store: store, credentials: credentials)
    }

    // MARK: - At launch

    @Test func aBuildWithoutCredentialsIsUnavailable() {
        let model = makeModel(credentials: nil)
        #expect(model.account == .unavailable)
        #expect(!model.canSignIn)
    }

    /// It can't be used here, but it is live at Google — so it has to be visible and endable, not
    /// hidden behind "not available".
    @Test func aSignInSavedByAnotherBuildCanStillBeEndedWithoutCredentials() async {
        let saved = token()
        let store = InMemoryTokenStore(saved)
        let model = makeModel(store: store, credentials: nil)
        #expect(model.account == .connected(expires: nil))
        #expect(
            UploadCopy.note(for: model.account, failure: nil, canSignIn: model.canSignIn)
                == "This build has no YouTube credentials, so it can't use this sign-in. Disconnect removes it.")

        let revoked = Recorder()
        model.revoke = { revoked.record($0) }
        await model.disconnect()

        #expect(revoked.tokens == [saved])
        #expect(store.load() == nil)
        #expect(model.account == .unavailable)
    }

    @Test func withNothingSavedItIsNotConnected() {
        let model = makeModel()
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == nil)
    }

    @Test func aSavedSignInReadsAsConnected() {
        #expect(makeModel(store: InMemoryTokenStore(token())).account == .connected(expires: nil))
        let ending = makeModel(store: InMemoryTokenStore(token(endsIn: 86_400)))
        #expect(ending.account == .connected(expires: now.addingTimeInterval(86_400)))
    }

    /// Google said when it would stop working; calling it connected past that would be a lie the
    /// next upload exposes.
    @Test func aSignInPastItsAnnouncedEndIsDroppedAtLaunch() {
        let store = InMemoryTokenStore(token(endsIn: -60))
        let model = makeModel(store: store)
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "The last sign-in has ended. Connect again.")
        #expect(store.load() == nil)
    }

    @Test func aSignInThatCannotBeReadIsNotConnected() {
        #expect(makeModel(store: BrokenStore(failsOn: .load)).account == .disconnected)
    }

    /// The app runs for days: an end date that passes while it is open is checked again, not only
    /// at launch.
    @Test func aSignInThatEndsWhileTheAppIsOpenIsDroppedWhenNextLookedAt() {
        let store = InMemoryTokenStore(token(endsIn: 3600))
        let model = makeModel(store: store)
        model.expireEndedSignIn(now: now.addingTimeInterval(3599))
        #expect(model.account == .connected(expires: now.addingTimeInterval(3600)))

        model.expireEndedSignIn(now: now.addingTimeInterval(3600))
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "The last sign-in has ended. Connect again.")
        #expect(store.load() == nil)
    }

    @Test func aSignInWithNoAnnouncedEndNeverExpiresByTheClock() {
        let model = makeModel(store: InMemoryTokenStore(token()))
        model.expireEndedSignIn(now: .distantFuture)
        #expect(model.account == .connected(expires: nil))
    }

    // MARK: - Connecting

    @Test func connectingOpensTheBrowserAndSavesTheSignIn() async {
        let store = InMemoryTokenStore()
        let model = makeModel(store: store)
        let granted = token(endsIn: 604_799)
        let url = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?x=1")!
        var opened: [URL] = []
        var cameToFront = 0
        model.openURL = {
            opened.append($0)
            return true
        }
        model.bringToFront = { cameToFront += 1 }
        model.signIn = { _, open in
            try await open(url)
            return granted
        }

        model.connect()
        #expect(model.account == .connecting)
        await model.connectTask?.value

        #expect(model.account == .connected(expires: granted.refreshTokenExpiry))
        #expect(store.load() == granted)
        #expect(opened == [url])
        #expect(cameToFront == 1)
        #expect(model.lastFailure == nil)
    }

    /// What the Trim window waits on before it opens the sheet: the outcome, not the start.
    @Test func waitingForASignInReturnsOnceItHasItsOutcome() async {
        let model = makeModel()
        model.signIn = { _, _ in throw GoogleSignInError.denied }
        await model.connectAndWait()
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "Sign-in was cancelled in the browser.")

        model.signIn = { [granted = token()] _, _ in granted }
        await model.connectAndWait()
        #expect(model.account == .connected(expires: nil))
    }

    @Test func aDeclinedSignInGoesBackWithTheReason() async {
        let store = InMemoryTokenStore()
        let model = makeModel(store: store)
        var cameToFront = 0
        model.bringToFront = { cameToFront += 1 }
        model.signIn = { _, _ in throw GoogleSignInError.denied }

        model.connect()
        await model.connectTask?.value

        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "Sign-in was cancelled in the browser.")
        #expect(store.load() == nil)
        #expect(cameToFront == 1)
    }

    /// Nothing opened, so no redirect will ever come: said at once, not after five minutes.
    @Test func aBrowserThatDoesNotOpenFailsTheSignInAtOnce() async {
        let model = makeModel()
        model.openURL = { _ in false }
        model.signIn = { [granted = token()] _, open in
            try await open(URL(string: "https://accounts.google.com/")!)
            return granted
        }
        model.connect()
        await model.connectTask?.value
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "Couldn't open the browser.")
    }

    /// The cancel can lose a race with Google. A grant that arrives after it is neither kept nor
    /// left live.
    @Test func aSignInThatArrivesAfterCancelIsRevokedNotKept() async {
        let store = InMemoryTokenStore()
        let model = makeModel(store: store)
        let granted = token()
        let revoked = Recorder()
        let gate = Gate()
        model.revoke = { revoked.record($0) }
        model.signIn = { _, _ in
            await gate.wait()
            return granted
        }

        model.connect()
        let waiting = model.connectTask
        model.cancelConnect()
        gate.open()
        await waiting?.value
        for _ in 0..<50 where revoked.tokens.isEmpty { await Task.yield() }

        #expect(model.account == .disconnected)
        #expect(store.load() == nil)
        #expect(revoked.tokens == [granted])
        #expect(model.lastFailure == nil)
    }

    /// URLSession reports a cancelled request as a network error; pressed here, it isn't one.
    @Test func aCancelThatSurfacesAsANetworkErrorIsStillACancel() async {
        let model = makeModel()
        var cameToFront = 0
        model.bringToFront = { cameToFront += 1 }
        let gate = Gate()
        model.signIn = { _, _ in
            await gate.wait()
            throw URLError(.cancelled)
        }
        model.connect()
        let waiting = model.connectTask
        model.cancelConnect()
        gate.open()
        await waiting?.value
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == nil)
        #expect(cameToFront == 0)
    }

    /// Cancelled from the Settings window itself: nothing to explain, nowhere to come back from.
    @Test func cancellingASignInExplainsNothing() async {
        let model = makeModel()
        var cameToFront = 0
        model.bringToFront = { cameToFront += 1 }
        model.signIn = { _, _ in
            try await Task.sleep(for: .seconds(60))
            throw GoogleSignInError.malformedResponse
        }

        model.connect()
        let waiting = model.connectTask
        model.cancelConnect()
        await waiting?.value

        #expect(model.account == .disconnected)
        #expect(model.lastFailure == nil)
        #expect(cameToFront == 0)
    }

    @Test func connectDoesNothingUnlessThereIsSomethingToConnect() async {
        let calls = Counter()
        for model in [makeModel(credentials: nil), makeModel(store: InMemoryTokenStore(token()))] {
            let before = model.account
            model.signIn = { _, _ in
                calls.increment()
                throw GoogleSignInError.denied
            }
            model.connect()
            await model.connectTask?.value
            #expect(model.account == before)
        }
        #expect(calls.value == 0)
    }

    @Test func theNextAttemptClearsTheLastFailure() async {
        let model = makeModel()
        model.signIn = { _, _ in throw LoopbackError.timedOut }
        model.connect()
        await model.connectTask?.value
        #expect(model.lastFailure == "Nothing came back from the browser in 5 minutes.")

        model.signIn = { _, _ in
            try await Task.sleep(for: .seconds(60))
            throw GoogleSignInError.denied
        }
        model.connect()
        #expect(model.lastFailure == nil)
        model.cancelConnect()
        await model.connectTask?.value
    }

    /// A grant that can't be kept must not stay live at Google with nothing here able to end it.
    @Test func aSignInThatCannotBeSavedIsRevoked() async {
        let model = makeModel(store: BrokenStore(failsOn: .save))
        let revoked = Counter()
        model.signIn = { [granted = token()] _, _ in granted }
        model.revoke = { _ in revoked.increment() }

        model.connect()
        await model.connectTask?.value
        for _ in 0..<50 where revoked.value == 0 { await Task.yield() }

        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "The sign-in didn't complete. Try again.")
        #expect(revoked.value == 1)
    }

    // MARK: - Disconnecting

    @Test func disconnectingRevokesTheSignInThenRemovesIt() async {
        let saved = token()
        let store = InMemoryTokenStore(saved)
        let model = makeModel(store: store)
        let revoked = Recorder()
        model.revoke = { revoked.record($0) }

        await model.disconnect()

        #expect(revoked.tokens == [saved])
        #expect(store.load() == nil)
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == nil)
    }

    /// The revoke can take as long as a stalled network lets it; the row says so meanwhile.
    @Test func whileGoogleIsBeingToldTheAccountIsDisconnecting() async {
        let model = makeModel(store: InMemoryTokenStore(token()))
        let gate = Gate()
        model.revoke = { _ in await gate.wait() }

        let disconnect = Task { await model.disconnect() }
        for _ in 0..<50 where model.account != .disconnecting { await Task.yield() }
        #expect(model.account == .disconnecting)
        #expect(UploadCopy.status(model.account) == "Disconnecting…")

        gate.open()
        await disconnect.value
        #expect(model.account == .disconnected)
    }

    /// No request was made, so Google is not to blame — and staying "connected" to a file nobody
    /// can read would leave the row stuck.
    @Test func aSignInThatCannotBeReadAtDisconnectIsDroppedAndSaidSo() async {
        let store = BrokenStore(failsOn: nil, holding: token())
        let model = makeModel(store: store)
        #expect(model.account == .connected(expires: nil))
        let revoked = Counter()
        model.revoke = { _ in revoked.increment() }

        store.failing = .load
        await model.disconnect()

        #expect(model.account == .disconnected)
        #expect(revoked.value == 0)
        #expect(model.lastFailure == "The saved sign-in couldn't be read, so Google wasn't told. You can remove ScreenRec's access in your Google account.")
    }

    /// Kept on purpose: deleting it would leave a live grant nothing on this Mac could end.
    @Test func aDisconnectThatCannotReachGoogleKeepsTheSignIn() async {
        let saved = token()
        let store = InMemoryTokenStore(saved)
        let model = makeModel(store: store)
        model.revoke = { _ in throw URLError(.notConnectedToInternet) }

        await model.disconnect()

        #expect(model.account == .connected(expires: nil))
        #expect(store.load() == saved)
        #expect(model.lastFailure == "Couldn't reach Google, so you are still connected.")
    }

    @Test func aRefusedRevocationKeepsItTooAndSaysSo() async {
        let model = makeModel(store: InMemoryTokenStore(token()))
        model.revoke = { _ in throw GoogleSignInError.rejected(error: "http_503", description: nil) }
        await model.disconnect()
        #expect(model.account == .connected(expires: nil))
        #expect(model.lastFailure == "Google couldn't end the sign-in just now, so you are still connected.")
    }

    @Test func aRevokedSignInWhoseCopyWillNotGoIsReportedAsThat() async {
        let model = makeModel(store: BrokenStore(failsOn: .delete, holding: token()))
        model.revoke = { _ in }
        await model.disconnect()
        #expect(model.account == .disconnected)
        #expect(model.lastFailure == "Google ended the sign-in, but the saved copy couldn't be removed from this Mac.")
    }

    @Test func disconnectDoesNothingWhenNotConnected() async {
        let model = makeModel()
        let revoked = Counter()
        model.revoke = { _ in revoked.increment() }
        await model.disconnect()
        #expect(model.account == .disconnected)
        #expect(revoked.value == 0)
    }

    // MARK: - The words

    @Test func eachStateHasItsStatus() {
        #expect(UploadCopy.status(.unavailable) == "Not available in this build")
        #expect(UploadCopy.status(.disconnected) == "Not connected")
        #expect(UploadCopy.status(.connecting) == "Waiting for Google in your browser…")
        #expect(UploadCopy.status(.connected(expires: nil)) == "Connected")
        #expect(UploadCopy.status(.connected(expires: now)) == "Connected")
        #expect(UploadCopy.status(.disconnecting) == "Disconnecting…")
    }

    /// Google announces the end only for a project still in Testing; the row passes it on rather
    /// than letting the sign-in stop working unannounced.
    @Test func aSignInWithAnAnnouncedEndSaysWhen() throws {
        let end = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12)))
        let note = UploadCopy.note(
            for: .connected(expires: end), failure: nil, canSignIn: true,
            locale: Locale(identifier: "en_GB"))
        #expect(note == "This sign-in ends on 23 November because the Google project behind this build is still in testing.")
    }

    @Test func theNoteIsAFailureFirstAndOtherwiseOnlyWhatTheStateNeeds() {
        for quiet in [UploadModel.Account.disconnected, .connecting, .disconnecting, .connected(expires: nil)] {
            #expect(UploadCopy.note(for: quiet, failure: nil, canSignIn: true) == nil, "\(quiet)")
        }
        #expect(
            UploadCopy.note(for: .unavailable, failure: nil, canSignIn: false)
                == "This build has no YouTube credentials.")
        #expect(
            UploadCopy.note(for: .connected(expires: now), failure: "Why not.", canSignIn: true)
                == "Why not.")
    }

    /// A link only where the README has the answer, and never beside a failure, which is its own
    /// explanation.
    @Test func theNoteLinksToTheReadmeOnlyWhereItHelps() {
        #expect(UploadCopy.noteLink(for: .unavailable, failure: nil, canSignIn: false) == "How to add them")
        #expect(UploadCopy.noteLink(for: .connected(expires: nil), failure: nil, canSignIn: false) == "How to add them")
        #expect(UploadCopy.noteLink(for: .connected(expires: now), failure: nil, canSignIn: true) == "What to do")
        #expect(UploadCopy.noteLink(for: .connected(expires: nil), failure: nil, canSignIn: true) == nil)
        #expect(UploadCopy.noteLink(for: .disconnected, failure: nil, canSignIn: true) == nil)
        #expect(UploadCopy.noteLink(for: .connected(expires: now), failure: "Why not.", canSignIn: true) == nil)
    }

    @Test func everyVisibilityIsOfferedNamedAndExplained() {
        #expect(UploadCopy.visibilityChoices == [.unlisted, .private, .public])
        #expect(Set(UploadCopy.visibilityChoices) == Set(VideoMetadata.Privacy.allCases))
        #expect(UploadCopy.visibilityChoices.map(UploadCopy.visibilityLabel) == ["Unlisted", "Private", "Public"])
        let captions = Set(UploadCopy.visibilityChoices.map(UploadCopy.visibilityCaption))
        #expect(captions.count == 3)
        #expect(UploadCopy.visibilityCaption(.unlisted) == "Anyone with the link can watch. It isn't shown on your channel.")
    }

    // MARK: - In the app's state

    /// What every other test gets: an account that reads nothing from disk and can't sign in.
    @Test func anAppStateBuiltWithoutAnAccountHasNone() {
        #expect(AppState(defaults: TestDefaults.make()).uploads.account == .unavailable)
    }

    @Test func theDefaultVisibilityIsUnlistedAndPersists() {
        let defaults = TestDefaults.make()
        let state = AppState(defaults: defaults)
        #expect(state.uploadVisibility == .unlisted)
        state.uploadVisibility = .private
        #expect(defaults.string(forKey: "youtubeVisibility") == "private")
        #expect(AppState(defaults: defaults).uploadVisibility == .private)
    }

    /// A value this build doesn't know falls back to the default rather than to the widest.
    @Test func aStoredVisibilityThisBuildDoesNotKnowIsUnlisted() {
        let defaults = TestDefaults.make()
        for stored in ["PUBLIC", "everyone", ""] {
            defaults.set(stored, forKey: "youtubeVisibility")
            #expect(SettingsStore.load(from: defaults).uploadVisibility == .unlisted, "\(stored)")
        }
        defaults.set(7, forKey: "youtubeVisibility")
        #expect(SettingsStore.load(from: defaults).uploadVisibility == .unlisted)
    }
}

// MARK: - Fakes

/// A store whose one chosen operation fails, for the paths a real disk makes rare.
private final class BrokenStore: TokenStore, @unchecked Sendable {
    enum Operation { case load, save, delete }

    /// Settable, so a store can read fine at launch and fail later.
    var failing: Operation?
    private let held: GoogleToken?

    init(failsOn failing: Operation?, holding held: GoogleToken? = nil) {
        self.failing = failing
        self.held = held
    }

    func load() throws -> GoogleToken? {
        if failing == .load { throw CocoaError(.fileReadNoPermission) }
        return held
    }
    func save(_ token: GoogleToken) throws {
        if failing == .save { throw CocoaError(.fileWriteNoPermission) }
    }
    func delete() throws {
        if failing == .delete { throw CocoaError(.fileWriteNoPermission) }
    }
}

/// Holds a fake sign-in or revocation open until the test lets it through.
private final class Gate: @unchecked Sendable {
    private let (stream, continuation) = AsyncStream<Void>.makeStream()

    func wait() async { for await _ in stream { return } }
    func open() { continuation.yield() }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [GoogleToken] = []

    func record(_ token: GoogleToken) { lock.withLock { recorded.append(token) } }
    var tokens: [GoogleToken] { lock.withLock { recorded } }
}
