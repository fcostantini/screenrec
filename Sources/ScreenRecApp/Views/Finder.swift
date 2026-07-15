import AppCore
import AppKit
import CoreGraphics

/// The AppKit edges AppCore can't reach across: enumerating screens and talking to Finder.
/// Both are one-liners over NSScreen/NSWorkspace — they live here only because AppCore may not
/// import AppKit (docs/01), which is also what keeps the logic on the other side testable.

extension DisplayOption {
    /// The displays the user can pick, in the system's own order.
    ///
    /// `NSScreenNumber` is the `CGDirectDisplayID` SCK resolves against — the same identifier
    /// `DisplaySelection.id` carries — so a menu pick survives the trip into a capture. A screen
    /// without one can't be captured and would be a dead menu row, so it's dropped.
    /// `isMain` comes from `CGMainDisplayID()`, not `NSScreen.main`. They are different
    /// questions: `NSScreen.main` is wherever the keyboard focus happens to be, so on a
    /// two-display Mac the "default" display would follow the frontmost window around. The
    /// default here has to mean the same thing `DisplaySelection.main` means to the engine —
    /// the primary display — or the checkmark and the capture disagree.
    static func liveScreens() -> [DisplayOption] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayOption(
                id: number.uint32Value, name: screen.localizedName,
                isMain: number.uint32Value == mainID)
        }
    }
}

enum Finder {
    /// docs/06 items 9–10: opening the folder, and clicking a recent recording, both land the
    /// user in Finder with the thing selected.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ directory: URL) {
        NSWorkspace.shared.open(directory)
    }
}
