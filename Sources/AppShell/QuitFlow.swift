import AppCore
import AppKit

/// Quitting, with the confirmations docs/06 item 12 requires: a recording is finalized before exit
/// (ADR-007) and an export in flight is never dropped without asking (M23-T2).
///
/// Shared, because ⌘Q in the app menu must do what the status item's `Quit` row does (ADR-023).
@MainActor
enum QuitFlow {

    static func run(_ state: AppState) {
        if state.session.isActive {
            guard ConfirmAlert.ask(
                "Stop recording and quit?", "Your recording will be saved first.",
                first: "Stop & Quit", second: "Keep Recording")
            else { return }
            Task {
                await state.finishWorkInFlight()
                NSApplication.shared.terminate(nil)
            }
            return
        }

        guard state.exports.exportInProgress != nil else { return NSApplication.shared.terminate(nil) }

        let outstanding = 1 + state.exports.queuedExportCount
        guard ConfirmAlert.ask(
            outstanding == 1 ? "An export is still running." : "\(outstanding) exports are still running.",
            outstanding == 1
                ? "Quitting now throws it away. The recording it came from is untouched."
                : "Quitting now throws them away. The recordings they came from are untouched.",
            first: "Wait for Export", second: "Quit Anyway")
        else {
            // Abandon it first: `terminate` runs `applicationShouldTerminate`, which waits for an
            // export in flight — so without this, "Quit Anyway" would wait like the other button.
            state.exports.cancelExport()
            return NSApplication.shared.terminate(nil)
        }

        Task {
            await state.exports.waitForExportToFinish()
            NSApplication.shared.terminate(nil)
        }
    }
}
