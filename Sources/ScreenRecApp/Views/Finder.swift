import AppCore
import AppKit
import CoreGraphics

/// The AppKit edges AppCore can't reach across: enumerating screens and talking to Finder.
/// They live here because AppCore may not import AppKit (docs/01).

extension DisplayOption {
    /// The displays the user can pick, in the system's own order.
    ///
    /// `NSScreenNumber` is the `CGDirectDisplayID` SCK resolves against; a screen without one
    /// can't be captured, so it's dropped. `isMain` uses `CGMainDisplayID()`, not `NSScreen.main`
    /// — the latter follows keyboard focus, so the default would drift on a two-display Mac.
    static func liveScreens() -> [DisplayOption] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayOption(
                id: number.uint32Value, name: screen.localizedName,
                isMain: number.uint32Value == mainID,
                pointSize: screen.frame.size, pointPixelScale: screen.backingScaleFactor)
        }
    }
}

enum Finder {
    /// docs/06 items 9–10: lands the user in Finder with the file selected.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ directory: URL) {
        NSWorkspace.shared.open(directory)
    }
}
