import CoreGraphics
import Foundation

/// One entry in the menu's `Display ▸` submenu (docs/06 item 5).
///
/// AppCore can't name `NSScreen` (no-AppKit rule), so the app enumerates screens and passes
/// these in — which also makes the picker testable without a second monitor.
public struct DisplayOption: Sendable, Equatable, Identifiable {
    /// Matches `DisplaySelection.id`, so a selection can be compared against the live list.
    public let id: CGDirectDisplayID
    /// `NSScreen.localizedName` — "Built-in Retina Display".
    public let name: String
    /// Which row to check when the user hasn't chosen one.
    public let isMain: Bool
    /// `NSScreen.frame.size` and `backingScaleFactor`; multiplied they give the pixel size SCK
    /// captures at (measured: 2056×1285 pt × 2 = the 4112×2570 frames we get). `.zero`/`1` mean
    /// the caller didn't supply geometry, and estimates built on it must be withheld, not guessed.
    public let pointSize: CGSize
    public let pointPixelScale: CGFloat

    public init(
        id: CGDirectDisplayID, name: String, isMain: Bool,
        pointSize: CGSize = .zero, pointPixelScale: CGFloat = 1
    ) {
        self.id = id
        self.name = name
        self.isMain = isMain
        self.pointSize = pointSize
        self.pointPixelScale = pointPixelScale
    }
}
