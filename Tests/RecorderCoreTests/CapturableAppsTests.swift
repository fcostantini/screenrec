import Testing
@testable import RecorderCore

@Suite struct CapturableAppsTests {

    @Test func sortsByNameCaseInsensitively() {
        let apps = CapturableApps.select([
            ("com.example.zed", "zed"),
            ("com.example.alpha", "Alpha"),
            ("com.example.beta", "beta"),
        ])
        #expect(apps.map(\.name) == ["Alpha", "beta", "zed"])
    }

    @Test func dropsEmptyBundleIDsAndDeduplicates() {
        let apps = CapturableApps.select([
            ("", "Nameless"),
            ("com.example.app", "App"),
            ("com.example.app", "App again"),
        ])
        #expect(apps == [CapturableApp(bundleID: "com.example.app", name: "App")])
    }

    @Test func fallsBackToBundleIDWhenNameIsEmpty() {
        let apps = CapturableApps.select([("com.example.app", "")])
        #expect(apps.first?.name == "com.example.app")
    }
}
