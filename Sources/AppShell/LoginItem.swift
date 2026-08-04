import AppCore
import ServiceManagement

/// `SMAppService.mainApp` wrapper — the real launch-at-login backing (docs/06, M6-T5). Registration
/// works for the self-signed dev build (measured); no Developer ID needed. macOS posts its own
/// "Login Item Added" banner on register, which is the user's confirmation.
@MainActor
struct SMLoginItem: LoginItemManaging {
    private var status: SMAppService.Status { SMAppService.mainApp.status }

    // Registered counts whether or not the user has approved it in System Settings — both mean
    // "the login item exists", which is what the toggle reflects. Only `.notRegistered`/`.notFound`
    // read as off.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
