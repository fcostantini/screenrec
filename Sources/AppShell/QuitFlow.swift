import AppCore
import AppKit

/// Quitting, with the confirmations docs/06 item 12 requires: a recording is finalized before exit
/// (ADR-007), and an export or an upload in flight is never dropped without saying so (M23-T2,
/// M40-T4). What is asked is `QuitQuestion`'s. An upload is waited for only when the user picks
/// the button that says so.
///
/// Shared, because ⌘Q in the app menu must do what the status item's `Quit` row does (ADR-023).
@MainActor
enum QuitFlow {

    static func run(_ state: AppState) {
        if state.session.isActive {
            guard ConfirmAlert.ask(
                "Stop recording and quit?", state.stopRecordingQuitBody,
                first: "Stop & Quit", second: "Keep Recording")
            else { return }
            Task {
                let announced = await state.finishWorkBeforeQuitting()
                await terminate(afterNotice: announced)
            }
            return
        }

        guard let question = state.quitQuestion else { return NSApplication.shared.terminate(nil) }

        guard ConfirmAlert.ask(
            question.title, question.body, first: question.wait, second: QuitQuestion.quitAnyway)
        else {
            // Abandon them first: `terminate` runs `applicationShouldTerminate`, which waits for
            // work in flight — so without this, "Quit Anyway" would wait like the other button.
            let announced = state.abandonExportsAndUploads()
            Task { await terminate(afterNotice: announced) }
            return
        }

        Task {
            await state.finishWorkInFlight()
            NSApplication.shared.terminate(nil)
        }
    }

    /// A notice posted on the way out needs a moment to leave the process before it exits.
    static let noticeGrace = Duration.milliseconds(300)

    private static func terminate(afterNotice announced: Bool) async {
        if announced { try? await Task.sleep(for: noticeGrace) }
        NSApplication.shared.terminate(nil)
    }
}
