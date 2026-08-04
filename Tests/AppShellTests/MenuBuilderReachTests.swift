import Foundation
import Testing

@testable import AppCore
@testable import AppShell

/// Proves the split did what it was for: the menu can be built and inspected **in a test**, with no
/// app deployed, no menu open and no Accessibility. Everything it touches is `internal` — only
/// `@testable import` reaches it.
///
/// One assertion deliberately: M29-T2 is where the menu's structure gets pinned properly.
@MainActor
@Suite struct MenuBuilderReachTests {

    @Test func theIdleMenuCanBeBuiltWithoutAMenu() {
        let defaults = UserDefaults(suiteName: "AppShellTests-\(UUID().uuidString)")!
        let state = AppState(defaults: defaults)
        let rows = MenuBuilder(
            state: state, windows: WindowPresenter(), thumbnails: MenuThumbnails()
        ).rows()

        let titles = rows.map(\.title)
        #expect(titles.contains("Start Recording"))
        #expect(titles.last == "Quit")
    }
}
