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

    private let credentials: GoogleClientCredentials?
    private let store: any TokenStore
    /// The sign-in in flight, readable so a test can wait for its outcome.
    private(set) var connectTask: Task<Void, Never>?
    /// Set by `cancelConnect`: whatever the sign-in in flight comes back with is no longer wanted.
    private var cancelRequested = false
    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "upload")

    public init(
        credentials: GoogleClientCredentials?, store: any TokenStore, now: Date = Date()
    ) {
        self.credentials = credentials
        self.store = store
        account = credentials == nil ? .unavailable : .disconnected
        do {
            if let saved = try store.load() { account = .connected(expires: saved.refreshTokenExpiry) }
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
            store: FileTokenStore(url: FileTokenStore.standardURL(named: "youtube-sign-in")))
    }

    /// Where the account lands when nothing is saved.
    private var signedOut: Account { canSignIn ? .disconnected : .unavailable }

    /// Drops a sign-in that has passed the end Google announced for it. Called at launch and each
    /// time the account is about to be shown or used: this app runs for days, and "connected, ends
    /// on a date already gone" is a claim it can check for itself.
    public func expireEndedSignIn(now: Date = Date()) {
        guard case .connected(let end?) = account, end <= now else { return }
        account = signedOut
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

        let saved: GoogleToken?
        do {
            saved = try store.load()
        } catch {
            // Nothing readable means nothing to send Google, and staying "connected" to a file
            // that can't be read helps nobody.
            Self.log.error("sign-in unreadable: \(error.localizedDescription, privacy: .public)")
            try? store.delete()
            account = signedOut
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
        account = signedOut
        do {
            try store.delete()
        } catch {
            Self.log.error("sign-in not removed: \(error.localizedDescription, privacy: .public)")
            lastFailure = UploadCopy.savedCopyNotRemoved
        }
    }
}

enum UploadModelError: Error {
    /// The system opened nothing for the sign-in URL, so no redirect will ever come.
    case browserDidNotOpen
}
