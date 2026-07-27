import CoreGraphics
import ScreenCaptureKit

/// A window the capture engine can scope to (`ContentSelection.window`), decoupled from
/// ScreenCaptureKit so the CLI and app can list windows without importing it.
public struct CapturableWindow: Sendable, Equatable {
    public let id: CGWindowID
    public let appName: String
    public let title: String
    /// `SCWindow.frame`'s size, in display points. The recorded pixel size is this times the
    /// display's backing scale (docs/02 §1c).
    public let pointSize: CGSize

    public init(id: CGWindowID, appName: String, title: String, pointSize: CGSize) {
        self.id = id
        self.appName = appName
        self.title = title
        self.pointSize = pointSize
    }
}

public enum CapturableWindows {
    /// Shown when a window carries no title of its own.
    public static let untitled = "(untitled)"
    /// Shown when a window reports no owning application.
    static let unknownApp = "(unknown)"

    /// On-screen windows, app-then-title sorted. Reads the same enumeration the engine resolves
    /// `.window` content against, so a listed window is always one capture can bind. Throws SCK's
    /// "user declined" when Screen Recording is ungranted (docs/02 §1).
    public static func available() async throws -> [CapturableWindow] {
        let content = try await SCShareableContent.forCapture()
        return select(content.windows.map {
            ($0.windowID, $0.windowLayer, $0.owningApplication?.applicationName, $0.title, $0.frame.size)
        })
    }

    /// Keep only ordinary user windows, sort by app then title. Pure.
    ///
    /// The `windowLayer == 0` filter is load-bearing: the enumeration also carries menu-bar
    /// extras (layer 25), the desktop and the Dock's wallpaper — 23 of the 32 windows measured
    /// on the dev machine, ScreenRec's own status item among them (docs/02 §1c).
    static func select(
        _ windows: [(id: CGWindowID, layer: Int, appName: String?, title: String?, pointSize: CGSize)]
    ) -> [CapturableWindow] {
        windows
            .compactMap { window -> CapturableWindow? in
                guard window.layer == 0, window.pointSize.width > 0, window.pointSize.height > 0
                else { return nil }
                let appName = window.appName.flatMap { $0.isEmpty ? nil : $0 } ?? unknownApp
                let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? untitled
                return CapturableWindow(
                    id: window.id, appName: appName, title: title, pointSize: window.pointSize)
            }
            .sorted {
                let byApp = $0.appName.localizedCaseInsensitiveCompare($1.appName)
                if byApp != .orderedSame { return byApp == .orderedAscending }
                let byTitle = $0.title.localizedCaseInsensitiveCompare($1.title)
                // Id last so two identically-named windows of one app keep a stable order.
                return byTitle == .orderedSame ? $0.id < $1.id : byTitle == .orderedAscending
            }
    }
}
