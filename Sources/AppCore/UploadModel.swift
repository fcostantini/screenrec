import Foundation
import Observation
import UploadCore
import os

/// The YouTube account (M40-T2, ADR-024), split out of `AppState` the way `ExportModel` is: whether
/// this build can sign in, whether someone has, and the connect and disconnect between the two.
///
/// It makes **no request at launch**: "connected" means a sign-in is saved. One that Google has
/// since dropped is found out when it is next used.
@MainActor
@Observable
public final class UploadModel {

    public enum Account: Equatable, Sendable {
        /// This build carries no Google credentials and no sign-in is saved: nothing to do here.
        case unavailable
        case disconnected
        /// Google's pages are in the browser and the app is waiting for the redirect.
        case connecting
        /// A sign-in is saved. `expires` is the end Google announced for it — only a Cloud project
        /// still in Testing has one (07).
        case connected(expires: Date?)
        /// Google is being told; the saved copy goes once it has answered.
        case disconnecting
    }

    public private(set) var account: Account

    /// Why the last connect or disconnect didn't take, for the line under the account row. The
    /// next attempt clears it.
    public private(set) var lastFailure: String?

    /// Whether this build carries the credentials a sign-in needs. A sign-in saved by another build
    /// still shows as connected without them — it can't be used here, but it can be ended.
    public var canSignIn: Bool { credentials != nil }

    /// Opens the sign-in in the browser and says whether anything opened. Injected by the app —
    /// `NSWorkspace` is AppKit, which AppCore may not import (docs/01).
    public var openURL: (@MainActor (URL) -> Bool)?
    /// Brings the app back in front of the browser once the sign-in has an outcome to show.
    public var bringToFront: (@MainActor () -> Void)?

    /// The browser sign-in and the revocation, injected so tests exercise every transition without
    /// a browser or a network. Default to `UploadCore`'s.
    public var signIn: @Sendable (
        _ credentials: GoogleClientCredentials,
        _ open: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> GoogleToken = { credentials, open in
        try await GoogleSignIn.signIn(credentials: credentials, open: open)
    }
    public var revoke: @Sendable (GoogleToken) async throws -> Void = {
        try await GoogleSignIn.revoke($0, transport: URLSessionTransport())
    }

    /// The title of the upload running now, or nil. Uploads run **one at a time**, in the order
    /// asked for; the rest wait in `pendingUploads`.
    public private(set) var uploadInProgress: String?
    /// How far it has got, 0…1.
    public private(set) var uploadProgress: Double?
    /// The transfer broke and is between tries at picking it up (M40-T5).
    public private(set) var uploadIsWaiting = false
    public var queuedUploadCount: Int { pendingUploads.count }

    /// The channel uploads land on, as YouTube named it with the last one (07) — the upload-only
    /// permission gives no way to ask before there has been one. Kept across launches.
    public private(set) var channelTitle: String?

    /// The upload that landed last, for the menu's receipt (M40-T4). Replaced by the next and
    /// kept across launches; seeded in `init`, where the observer does not fire.
    public private(set) var lastUpload: LastUpload? {
        didSet {
            guard lastUpload != oldValue, let defaults else { return }
            SettingsStore.saveLastUpload(lastUpload, to: defaults)
        }
    }

    /// The upload that failed last, for the menu's row and its `Try Again` (M40-T6). In memory
    /// only; replaced by a newer failure, gone when it is tried again or dismissed.
    public private(set) var failedUpload: FailedUpload?
    /// What that upload was asked with, and the session to continue if YouTube opened one.
    private var failedRequest: Request?

    /// Posts an upload's outcome. Wired by AppState from its notifier; nil in tests.
    public var notify: (@MainActor (RecordingNotification) -> Void)?

    /// The pasteboard's change counter and a write to it, injected by the app — `NSPasteboard` is
    /// AppKit (docs/01). Left unset, no link is ever copied.
    public var clipboardChangeCount: (@MainActor () -> Int)?
    public var copyToClipboard: (@MainActor (String) -> Void)?

    /// What a transfer is sent with (M40-T5): the access token, a way to renew it when YouTube
    /// says it has lapsed mid-upload, and where to say the transfer is waiting to be picked up.
    public struct UploadAccess: Sendable {
        public let token: String
        public let renew: @Sendable () async throws -> String
        public let waiting: @Sendable (Bool) -> Void
        /// The unfinished upload to pick up, when this is `Try Again` (M40-T6), and where the
        /// uploader says which session it opened and that the one to continue was gone.
        public let continuing: UploadSession?
        public let opened: @Sendable (UploadSession) -> Void
        public let startedOver: @Sendable () -> Void
    }

    /// The transfer and the token refresh, injected for the same reason as `signIn`.
    public var uploadFunction: @Sendable (
        _ file: URL, _ metadata: VideoMetadata, _ pass: UploadAccess,
        _ progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> UploadedVideo = { file, metadata, pass, progress in
        // Not named `access`: the Observation macro expands this initializer beside a function
        // of that name.
        try await YouTubeUploader().upload(
            file, metadata: metadata,
            accessToken: { renewed in renewed ? try await pass.renew() : pass.token },
            continuing: pass.continuing,
            events: .init(
                progress: progress, waiting: pass.waiting, opened: pass.opened,
                startedOver: pass.startedOver))
    }
    public var refresh: @Sendable (
        GoogleToken, GoogleClientCredentials
    ) async throws -> GoogleToken = { token, credentials in
        try await GoogleSignIn.refresh(
            token, credentials: credentials, transport: URLSessionTransport())
    }

    private let credentials: GoogleClientCredentials?
    private let store: any TokenStore
    private let defaults: UserDefaults?
    private var pendingUploads: [Request] = []
    /// Goes up each time a sign-in ends, so an upload can tell the one it began under has gone.
    private var signInsEnded = 0
    /// Tells one upload's progress reports from the next one's.
    private var uploadGeneration = 0
    /// The upload the user stopped, so its ending is not reported as a failure.
    private var cancelledGeneration: Int?
    /// The upload in flight, readable so a test can wait for the queue to drain.
    private(set) var uploadTask: Task<Void, Never>?
    /// The sign-in in flight, readable so a test can wait for its outcome.
    private(set) var connectTask: Task<Void, Never>?
    /// Set by `cancelConnect`: whatever the sign-in in flight comes back with is no longer wanted.
    private var cancelRequested = false
    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "upload")

    /// `defaults` is where the channel's name is kept; left out, it lasts only as long as the
    /// process.
    public init(
        credentials: GoogleClientCredentials?, store: any TokenStore,
        defaults: UserDefaults? = nil, now: Date = Date()
    ) {
        self.credentials = credentials
        self.store = store
        self.defaults = defaults
        lastUpload = defaults.flatMap(SettingsStore.loadLastUpload)
        account = credentials == nil ? .unavailable : .disconnected
        do {
            if let saved = try store.load() {
                account = .connected(expires: saved.refreshTokenExpiry)
                channelTitle = defaults?.string(forKey: SettingsStore.Key.youtubeChannel)
            }
        } catch {
            // Unreadable is not connected, and saying so beats a launch that fails over it.
            Self.log.error("sign-in unreadable: \(error.localizedDescription, privacy: .public)")
        }
        expireEndedSignIn(now: now)
    }

    /// What the app runs with: the credentials `Scripts/bundle.sh` stamped into the bundle, and the
    /// sign-in file in Application Support.
    public static func bundled() -> UploadModel {
        UploadModel(
            credentials: .bundled(),
            store: FileTokenStore(url: FileTokenStore.standardURL(named: "youtube-sign-in")),
            defaults: .standard)
    }

    /// Ends the sign-in as far as this model goes; the saved copy is the caller's to remove. The
    /// channel belongs to the sign-in, so its name goes too.
    private func signOut() {
        account = canSignIn ? .disconnected : .unavailable
        signInsEnded += 1
        channelTitle = nil
        defaults?.removeObject(forKey: SettingsStore.Key.youtubeChannel)
    }

    /// Whether the sign-in that was in use when `signInsEnded` read `count` still is.
    private func isCurrent(_ count: Int) -> Bool {
        guard case .connected = account else { return false }
        return count == signInsEnded
    }

    /// Drops a sign-in that has passed the end Google announced for it. Called at launch and each
    /// time the account is about to be shown or used: this app runs for days, and "connected, ends
    /// on a date already gone" is a claim it can check for itself.
    public func expireEndedSignIn(now: Date = Date()) {
        guard case .connected(let end?) = account, end <= now else { return }
        signOut()
        if canSignIn { lastFailure = UploadCopy.signInEnded }
        // Best effort: a copy left behind is judged the same way next time.
        try? store.delete()
    }

    // MARK: - Connecting

    /// Starts a sign-in in the browser. Returns at once; `account` carries the outcome.
    public func connect() {
        guard account == .disconnected, let credentials else { return }
        account = .connecting
        lastFailure = nil
        cancelRequested = false
        let signIn = signIn  // snapshot; the closure captures no `self`
        connectTask = Task { [weak self] in
            let outcome: Result<GoogleToken, any Error>
            do {
                outcome = .success(
                    try await signIn(credentials) { [weak self] url in
                        guard await self?.openURL?(url) == true else {
                            throw UploadModelError.browserDidNotOpen
                        }
                    })
            } catch {
                outcome = .failure(error)
            }
            self?.finishConnecting(outcome)
        }
    }

    /// `connect()`, returning once the sign-in has its outcome. `account` says which it was.
    public func connectAndWait() async {
        connect()
        await connectTask?.value
    }

    /// Gives up on a sign-in in flight. The browser tab is left as it is; its redirect, if it ever
    /// comes, finds nobody listening.
    public func cancelConnect() {
        guard account == .connecting else { return }
        cancelRequested = true
        connectTask?.cancel()
    }

    private func finishConnecting(_ outcome: Result<GoogleToken, any Error>) {
        connectTask = nil
        guard !cancelRequested else {
            // Pressed here, so there is nothing to explain and nothing to come forward for. The
            // cancel can lose a race with Google: a grant that arrived anyway is not kept.
            if case .success(let token) = outcome { revokeUnkept(token) }
            account = .disconnected
            return
        }
        do {
            let token = try outcome.get()
            do {
                try store.save(token)
            } catch {
                revokeUnkept(token)
                throw error
            }
            account = .connected(expires: token.refreshTokenExpiry)
        } catch {
            Self.log.error("connect failed: \(String(describing: error), privacy: .public)")
            account = .disconnected
            lastFailure = UploadCopy.connectFailure(error)
        }
        bringToFront?()
    }

    /// A grant that isn't being kept must not stay live at Google with nothing here able to end
    /// it. Best effort: whatever led here is the failure worth showing.
    private func revokeUnkept(_ token: GoogleToken) {
        let revoke = revoke
        Task { try? await revoke(token) }
    }

    // MARK: - Disconnecting

    /// Withdraws the sign-in with Google, then removes the saved copy. If Google can't be told,
    /// the sign-in is **kept**: deleting it would leave a live grant nothing here could end.
    public func disconnect() async {
        guard case .connected(let expires) = account else { return }
        account = .disconnecting
        lastFailure = nil
        defer {
            let waiters = disconnectWaiters
            disconnectWaiters = []
            for waiter in waiters { waiter.resume() }
        }

        let saved: GoogleToken?
        do {
            saved = try store.load()
        } catch {
            // Nothing readable means nothing to send Google, and staying "connected" to a file
            // that can't be read helps nobody.
            Self.log.error("sign-in unreadable: \(error.localizedDescription, privacy: .public)")
            try? store.delete()
            signOut()
            lastFailure = UploadCopy.notWithdrawn
            return
        }
        if let saved {
            do {
                try await revoke(saved)
            } catch {
                Self.log.error("revoke failed: \(String(describing: error), privacy: .public)")
                account = .connected(expires: expires)
                lastFailure = UploadCopy.disconnectFailure(error)
                return
            }
        }
        signOut()
        do {
            try store.delete()
        } catch {
            Self.log.error("sign-in not removed: \(error.localizedDescription, privacy: .public)")
            lastFailure = UploadCopy.savedCopyNotRemoved
        }
    }

    // MARK: - Uploading

    private struct Request {
        var file: URL
        let metadata: VideoMetadata
        var clipboardMark: Int?
        /// The unfinished upload this one picks up, when it is a retry (M40-T6).
        var continuing: OpenUpload?
        /// An earlier attempt left an entry on YouTube that this one will not finish.
        var earlierEntryMayRemain = false
    }

    /// A session YouTube opened, and the sign-in it was opened under. It is continued only
    /// while that sign-in stands: the next one may be another account's, and an upload
    /// continued then could land on a channel the user has disconnected from.
    private struct OpenUpload: Sendable {
        let session: UploadSession
        let signIn: Int
    }

    /// The upload in flight: what was asked for; whether YouTube has heard of it — raised at the
    /// uploader's first report, from when YouTube holds an unfinished entry this app cannot
    /// delete (07); the session a retry would continue; and whether an earlier attempt's entry
    /// may still be there.
    private struct Running {
        var request: Request
        let reached = Locked(false)
        let open = Locked<OpenUpload?>(nil)
        let earlierEntry: Locked<Bool>

        init(request: Request) {
            self.request = request
            earlierEntry = Locked(request.earlierEntryMayRemain)
        }
    }

    /// A value written from the uploader's queue and read here, with no hop in between: a hop
    /// can arrive late or out of order, and what was said last is what has to be known.
    private final class Locked<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value

        init(_ value: Value) { stored = value }

        var value: Value {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private var running: Running?
    /// The app is quitting: nothing more is taken.
    private var isShutDown = false
    /// Uploads that met a disconnect in progress and are waiting to learn how it ended.
    private var disconnectWaiters: [CheckedContinuation<Void, Never>] = []

    /// Sends `file` to the connected channel (M40-T3). Returns at once: uploads run one at a time
    /// in the order asked for, and `notify` carries each outcome. The file is only read.
    ///
    /// `clipboardMark` is the pasteboard's change counter when the user confirmed the sheet, for
    /// a caller that had other work to do first; left out, it is read now.
    public func upload(_ file: URL, metadata: VideoMetadata, clipboardMark: Int? = nil) {
        guard !isShutDown else { return }
        pendingUploads.append(
            Request(
                file: file, metadata: metadata,
                clipboardMark: clipboardMark ?? clipboardChangeCount?()))
        startNextUploadIfIdle()
    }

    /// Everything not yet landed: the upload running and the ones behind it.
    public var outstandingUploadCount: Int {
        (uploadInProgress == nil ? 0 : 1) + pendingUploads.count
    }

    /// Names the upload running now, so a row built for it can stop that one and no other: the
    /// menu's rows are stamped at open, and the upload under them can change while it is up.
    public var currentUploadToken: Int? { uploadInProgress == nil ? nil : uploadGeneration }

    /// Whether stopping now would leave an unfinished entry on the channel.
    public var stoppedUploadLeavesEntry: Bool { running?.reached.value == true }

    /// Stops the upload `token` names (M40-T4), if it is still the one running. The clip stays
    /// where it is and the next one waiting starts.
    public func cancelUpload(_ token: Int) {
        guard uploadInProgress != nil, token == uploadGeneration else { return }
        cancelledGeneration = uploadGeneration
        announceStopped()
        uploadTask?.cancel()
    }

    /// Abandons the upload in flight and every one waiting — the user chose to quit through
    /// them. Cleared **synchronously**, as `ExportModel.cancelExport` is and for its reason: the
    /// quit that follows must see nothing in flight. True when a notice was posted.
    @discardableResult
    public func cancelAllUploads() -> Bool {
        pendingUploads.removeAll()
        guard uploadInProgress != nil else { return false }
        cancelledGeneration = uploadGeneration
        let announced = announceStopped()
        uploadTask?.cancel()
        uploadTask = nil
        uploadInProgress = nil
        uploadProgress = nil
        uploadIsWaiting = false
        running = nil
        return announced
    }

    /// For a quit nobody chose to wait through: every upload is abandoned and no more are taken,
    /// so an export still finishing cannot start one on its way out. True when a notice was posted.
    @discardableResult
    public func shutDown() -> Bool {
        isShutDown = true
        return cancelAllUploads()
    }

    /// Says what a stopped upload leaves behind — only when YouTube had opened it. One that never
    /// got that far leaves nothing, and nothing is said: the press is its own explanation.
    @discardableResult
    private func announceStopped() -> Bool {
        guard let running, running.reached.value else { return false }
        notify?(
            RecordingNotifications.uploadStopped(
                title: running.request.metadata.title, file: running.request.file))
        return true
    }

    /// Waits for the whole queue, not just the upload running now; returns at once when there is
    /// none. Each ending starts its successor before its task resolves.
    public func waitForUploadsToFinish() async {
        while uploadInProgress != nil || !pendingUploads.isEmpty {
            guard let task = uploadTask else { return }
            await task.value
        }
    }

    private func startNextUploadIfIdle() {
        guard uploadInProgress == nil, !pendingUploads.isEmpty else { return }
        let started = Running(request: pendingUploads.removeFirst())
        if let continuing = started.request.continuing {
            // YouTube already holds an entry for it, whatever happens next.
            started.open.value = continuing
            started.reached.value = true
        }
        running = started
        uploadGeneration += 1
        uploadInProgress = started.request.metadata.title
        uploadProgress = 0
        uploadTask = Task { [weak self, generation = uploadGeneration] in
            await self?.run(started, generation: generation)
        }
    }

    private func run(_ started: Running, generation: Int) async {
        let request = started.request
        let signIn = signInsEnded
        do {
            let video = try await send(started, signIn: signIn, generation: generation)
            // YouTube can leave the name out, and the account can have changed by now: neither
            // is a reason to drop or replace a name that is right.
            if let channel = video.channelTitle, isCurrent(signIn) {
                channelTitle = channel
                defaults?.set(channel, forKey: SettingsStore.Key.youtubeChannel)
            }
            Self.log.info("uploaded \(video.id, privacy: .public)")
            let title = video.title ?? request.metadata.title
            // Where the clip is now: it can have been renamed while it went up.
            let file = (generation == uploadGeneration ? running?.request.file : nil) ?? request.file
            lastUpload = LastUpload(videoID: video.id, title: title, file: file, date: Date())
            var earlierEntry = started.earlierEntry.value
            // The same clip had failed before and has now gone up another way: its row would
            // only offer to publish it twice. What that attempt left on YouTube is still there.
            if let failed = failedUpload, failed.file.isSameFile(as: file) {
                earlierEntry = earlierEntry || failed.leavesEntry
                dismissFailedUpload()
            }
            notify?(
                RecordingNotifications.uploaded(
                    title: title,
                    visibility: video.privacyStatus ?? request.metadata.privacy.rawValue,
                    link: video.link, file: file,
                    linkCopied: copyIfClipboardUntouched(video.link, since: request.clipboardMark),
                    earlierEntryMayRemain: earlierEntry))
        } catch where cancelledGeneration == generation {
            Self.log.info("upload cancelled")
        } catch {
            Self.log.error("upload failed: \(String(describing: error), privacy: .public)")
            let failure = UploadCopy.failure(for: error)
            // Only what Google itself refuses to renew: a token YouTube alone turned down still
            // stands at Google, and dropping it here would leave a grant nothing local can end.
            if failure == .signInEnded, isCurrent(signIn) {
                // Google no longer honours it — found out here, at its next use, since nothing
                // asks at launch — so calling the account connected would be untrue.
                signOut()
                lastFailure = UploadCopy.signInEnded
                try? store.delete()
            }
            let file = (generation == uploadGeneration ? running?.request.file : nil) ?? request.file
            let clipExists = FileManager.default.fileExists(atPath: file.path)
            let reached = started.reached.value
            // An expired session is YouTube letting go of the entry, not keeping it.
            let leavesEntry = reached && failure != .sessionLost
            // What a retry could continue: the session, unless YouTube has let go of it or the
            // sign-in it was opened under no longer stands.
            let open = failure == .sessionLost ? nil : started.open.value
            let continuing = open.flatMap { isCurrent($0.signIn) ? $0 : nil }
            // Whatever a retry will not finish stays behind, and the upload that finally lands
            // has to say so.
            let earlierEntry = started.earlierEntry.value || (reached && continuing == nil)
            failedRequest = Request(
                file: file, metadata: request.metadata, clipboardMark: nil,
                continuing: continuing, earlierEntryMayRemain: earlierEntry)
            failedUpload = FailedUpload(
                title: request.metadata.title, file: file, failure: failure, date: Date(),
                leavesEntry: leavesEntry || started.earlierEntry.value)
            notify?(
                RecordingNotifications.uploadFailed(
                    reason: UploadCopy.reason(failure, clipExists: clipExists),
                    title: request.metadata.title, file: file, clipExists: clipExists,
                    leavesEntry: leavesEntry,
                    retry: !failure.canRetry ? .none : continuing == nil ? .startsFresh : .continues,
                    earlierEntryMayRemain: started.earlierEntry.value))
        }
        // An abandoned queue has already been cleared, and a later upload may own these by now.
        guard generation == uploadGeneration, uploadInProgress != nil else { return }
        uploadInProgress = nil
        uploadProgress = nil
        uploadIsWaiting = false
        running = nil
        startNextUploadIfIdle()
    }

    // MARK: - Trying again

    /// Sends the failed upload again with what the sheet held (M40-T6) — continuing the same
    /// upload when YouTube opened one, so the entry it left becomes the video instead of a
    /// second one being made. The clipboard rule counts from here, as it does from the sheet.
    public func tryAgain() {
        guard !isShutDown, failedUpload?.canTryAgain == true, var request = failedRequest else {
            return
        }
        dismissFailedUpload()
        request.clipboardMark = clipboardChangeCount?()
        pendingUploads.append(request)
        startNextUploadIfIdle()
    }

    public func dismissFailedUpload() {
        failedUpload = nil
        failedRequest = nil
    }

    /// ADR-024's clipboard rule: the link goes on the clipboard only if nothing else has since
    /// the sheet was confirmed. True when it was written.
    private func copyIfClipboardUntouched(_ link: String, since mark: Int?) -> Bool {
        guard let mark, let copyToClipboard, clipboardChangeCount?() == mark else { return false }
        copyToClipboard(link)
        return true
    }

    // MARK: - The receipt

    /// Drops the receipt once it has aged past the export receipt's own window. Called at menu
    /// open with the others. The clip going missing is no reason: the link still works.
    public func expireStaleReceipt(now: Date = Date()) {
        if lastUpload?.isStale(now: now, freshFor: ExportModel.receiptFreshness) == true {
            lastUpload = nil
        }
    }

    /// What the menu needs settled before it is built: a sign-in past its announced end dropped,
    /// as Settings and the Trim window do before showing the account, and a receipt past its hour.
    public func prepareForMenu(now: Date = Date()) {
        expireEndedSignIn(now: now)
        expireStaleReceipt(now: now)
        if failedUpload?.isStale(now: now) == true { dismissFailedUpload() }
    }

    /// A clip was renamed: everything that names it follows — the receipt, keeping its date, and
    /// the uploads running and waiting, which would otherwise look for a file that has gone.
    public func fileRenamed(from oldURL: URL, to newURL: URL) {
        if let upload = lastUpload, upload.file.isSameFile(as: oldURL) {
            lastUpload = LastUpload(
                videoID: upload.videoID, title: upload.title, file: newURL, date: upload.date)
        }
        if running?.request.file.isSameFile(as: oldURL) == true { running?.request.file = newURL }
        for index in pendingUploads.indices where pendingUploads[index].file.isSameFile(as: oldURL) {
            pendingUploads[index].file = newURL
        }
        if failedRequest?.file.isSameFile(as: oldURL) == true {
            failedRequest?.file = newURL
            failedUpload?.file = newURL
        }
    }

    private func send(
        _ started: Running, signIn: Int, generation: Int
    ) async throws -> UploadedVideo {
        let request = started.request
        expireEndedSignIn()
        await disconnectOutcome()
        guard case .connected = account, let credentials, var token = try store.load() else {
            throw UploadModelError.notConnected
        }
        if token.needsRefresh() {
            token = try await refresh(token, credentials)
            // A disconnect can finish while Google answers; saving now would undo it.
            await disconnectOutcome()
            guard isCurrent(signIn) else { throw UploadModelError.notConnected }
            try store.save(token)
        }
        // The awaits above can outlast a cancel; nothing may start for an upload already stopped.
        try Task.checkCancellation()
        let total = try YouTubeUploader.fileSize(of: request.file)
        let pass = UploadAccess(
            token: token.accessToken,
            renew: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.renewedAccessToken(signIn: signIn)
            },
            waiting: waitingReporter(generation: generation),
            continuing: usableSession(of: started),
            opened: { [open = started.open, reached = started.reached] in
                open.value = OpenUpload(session: $0, signIn: signIn)
                reached.value = true
            },
            startedOver: { [started] in Self.forgetSession(of: started) })
        return try await uploadFunction(
            request.file, request.metadata, pass,
            progressReporter(total: total, generation: generation, reached: started.reached))
    }

    /// The session to continue, if its sign-in still stands. If not, the upload starts from
    /// nothing — and what the earlier attempt left on YouTube stays there.
    private func usableSession(of started: Running) -> UploadSession? {
        guard let open = started.open.value else { return nil }
        guard isCurrent(open.signIn) else {
            Self.forgetSession(of: started)
            return nil
        }
        return open.session
    }

    /// The upload is beginning again from nothing: YouTube holds nothing for *this* attempt
    /// yet, and the entry the earlier one left may still be there.
    private nonisolated static func forgetSession(of started: Running) {
        started.open.value = nil
        started.reached.value = false
        started.earlierEntry.value = true
    }

    /// A disconnect under way may yet fail and leave the account connected, so an upload that
    /// meets one waits for its outcome instead of being turned away on a guess.
    private func disconnectOutcome() async {
        guard account == .disconnecting else { return }
        await withCheckedContinuation { disconnectWaiters.append($0) }
    }

    /// The token renewed mid-upload: an upload can outlive the hour the first one lasts. A
    /// renewal Google refuses throws `signInExpired`, which is how a dead sign-in is found.
    private func renewedAccessToken(signIn: Int) async throws -> String {
        guard let credentials, let token = try store.load() else {
            throw UploadModelError.notConnected
        }
        let renewed = try await refresh(token, credentials)
        await disconnectOutcome()
        guard isCurrent(signIn) else { throw UploadModelError.notConnected }
        try store.save(renewed)
        return renewed.accessToken
    }

    /// Where the uploader says it is between tries. `generation` is the upload's own, handed in:
    /// read here it could already be a successor's, since `send` awaits before this is built.
    private func waitingReporter(generation: Int) -> @Sendable (Bool) -> Void {
        let latest = Locked(false)
        return { [weak self] waiting in
            latest.value = waiting
            Task { @MainActor in
                guard let self, generation == self.uploadGeneration, self.uploadInProgress != nil
                else { return }
                // Whatever was said last, not what this hop was sent with: hops can cross.
                self.uploadIsWaiting = latest.value
            }
        }
    }

    /// The sink handed to the uploader, which reports from URLSession's queue. A report from an
    /// upload that has since ended must not move its successor's bar.
    private func progressReporter(
        total: Int64, generation: Int, reached: Locked<Bool>
    ) -> @Sendable (Int64) -> Void {
        return { [weak self] sent in
            reached.value = true
            Task { @MainActor in
                guard let self, generation == self.uploadGeneration, self.uploadInProgress != nil
                else { return }
                self.uploadProgress = min(1, max(0, Double(sent) / Double(total)))
            }
        }
    }
}

enum UploadModelError: Error {
    /// The system opened nothing for the sign-in URL, so no redirect will ever come.
    case browserDidNotOpen
    /// An upload was asked for with no usable sign-in.
    case notConnected
}
