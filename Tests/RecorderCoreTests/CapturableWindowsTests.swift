import CoreGraphics
import Testing
@testable import RecorderCore

@Suite struct CapturableWindowsTests {

    private func window(
        id: CGWindowID, layer: Int = 0, bundleID: String? = "com.example.app",
        app: String? = "App", title: String? = "Title",
        size: CGSize = CGSize(width: 800, height: 600)
    ) -> (id: CGWindowID, layer: Int, bundleID: String?, appName: String?,
          title: String?, pointSize: CGSize) {
        (id: id, layer: layer, bundleID: bundleID, appName: app, title: title, pointSize: size)
    }

    @Test func keepsOnlyLayerZeroWindows() {
        // The enumeration also carries menu-bar extras (25), the desktop and the Dock's
        // wallpaper (large negatives) — 23 of 32 windows on the dev machine (docs/02 §1c).
        let windows = CapturableWindows.select([
            window(id: 1, layer: 0, app: "Finder", title: "Movies"),
            window(id: 2, layer: 25, app: "Control Center", title: "Clock"),
            window(id: 3, layer: -2_147_483_626, app: "Dock", title: "Wallpaper"),
            window(id: 4, layer: 2_147_483_630, app: "WindowServer", title: "StatusIndicator"),
        ])
        #expect(windows.map(\.id) == [1])
    }

    @Test func dropsZeroAreaWindows() {
        let windows = CapturableWindows.select([
            window(id: 1, size: CGSize(width: 0, height: 600)),
            window(id: 2, size: CGSize(width: 800, height: 0)),
            window(id: 3, size: CGSize(width: 800, height: 600)),
        ])
        #expect(windows.map(\.id) == [3])
    }

    @Test func sortsByAppThenTitleCaseInsensitively() {
        let windows = CapturableWindows.select([
            window(id: 1, app: "Terminal", title: "session"),
            window(id: 2, app: "finder", title: "Movies"),
            window(id: 3, app: "Finder", title: "dist"),
        ])
        #expect(windows.map(\.id) == [3, 2, 1])
    }

    @Test func identicallyNamedWindowsKeepAStableOrder() {
        let windows = CapturableWindows.select([
            window(id: 9, app: "Finder", title: "Movies"),
            window(id: 4, app: "Finder", title: "Movies"),
        ])
        #expect(windows.map(\.id) == [4, 9])
    }

    @Test func fillsInMissingTitleAndAppName() {
        let windows = CapturableWindows.select([
            window(id: 1, app: nil, title: nil),
            window(id: 2, app: "", title: ""),
        ])
        #expect(windows.allSatisfy { $0.title == CapturableWindows.untitled })
        #expect(windows.allSatisfy { $0.appName == CapturableWindows.unknownApp })
    }

    @Test func carriesTheOwningBundleIDForPickVerification() {
        // A persisted pick is verified against this, because window ids are reused (docs/02 §1c).
        let windows = CapturableWindows.select([window(id: 1, bundleID: "com.apple.Safari")])
        #expect(windows.first?.bundleID == "com.apple.Safari")
    }

    @Test func carriesThePointSizeThroughUnchanged() {
        // The recorded pixel size is this × the display's backing scale; the model stays in points.
        let windows = CapturableWindows.select([
            window(id: 1, size: CGSize(width: 920, height: 436))
        ])
        #expect(windows.first?.pointSize == CGSize(width: 920, height: 436))
    }
}
