import Foundation

/// The launch-at-login seam (docs/06). A protocol so `AppState` is testable without touching the
/// real `SMAppService`, which registers a system login item as a side effect — the concrete
/// `SMAppService.mainApp` wrapper lives in `AppShell`.
@MainActor
public protocol LoginItemManaging {
    /// Whether the app is registered to launch at login — true for both `.enabled` and
    /// `.requiresApproval` (registered, but the user must re-enable it in System Settings after
    /// having turned it off there). The OS is the source of truth; this reads live status.
    var isEnabled: Bool { get }
    /// The item is registered but sitting in `.requiresApproval`: `register()` succeeded yet macOS
    /// won't launch it until the user approves it in System Settings › General › Login Items.
    var needsApproval: Bool { get }
    /// Register or unregister the login item. Throws if the service refuses (surfaced to the log).
    func setEnabled(_ enabled: Bool) throws
}
