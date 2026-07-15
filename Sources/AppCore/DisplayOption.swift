import CoreGraphics
import Foundation

/// One entry in the menu's `Display ▸` submenu (docs/06 item 5).
///
/// AppCore can't name `NSScreen` — the no-AppKit rule — so the app enumerates the screens and
/// passes these in. That split is not a workaround: it's the same shape `Permissions` already
/// uses (pure decisions here, thin live queries at the edge), and it means the picker's logic
/// is testable without a second monitor, which this machine has never had.
public struct DisplayOption: Sendable, Equatable, Identifiable {
    /// Matches `DisplaySelection.id`, so a selection can be compared against the live list.
    public let id: CGDirectDisplayID
    /// `NSScreen.localizedName` — "Built-in Retina Display".
    public let name: String
    /// Which row to check when the user hasn't chosen one.
    public let isMain: Bool

    public init(id: CGDirectDisplayID, name: String, isMain: Bool) {
        self.id = id
        self.name = name
        self.isMain = isMain
    }
}
