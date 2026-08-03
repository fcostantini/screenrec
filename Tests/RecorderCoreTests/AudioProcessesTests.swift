import Foundation
import Testing

@testable import RecorderCore

/// Which app a sound belongs to (M27). Measured on the real thing: Discord's call audio comes from
/// `com.hnc.Discord.helper.Renderer`, a nested `.app` inside `Discord.app/Contents/Frameworks` — so
/// "mute Discord" has to reach the helper, and the menu has to say "Discord".
@Suite struct AudioProcessesTests {

    @Test func aHelperResolvesToTheAppItBelongsTo() {
        #expect(
            AudioProcesses.parentBundleID(of: "com.hnc.Discord.helper.Renderer") == "com.hnc.Discord")
        #expect(
            AudioProcesses.parentBundleID(of: "com.google.Chrome.helper") == "com.google.Chrome")
        // Case is not something to rely on in a bundle id.
        #expect(
            AudioProcesses.parentBundleID(of: "com.example.App.Helper.GPU") == "com.example.App")
    }

    @Test func anOrdinaryAppIsItsOwnParent() {
        // The common case must pass through untouched, or every app would be renamed.
        for bundleID in ["com.spotify.client", "com.apple.QuickTimePlayerX", "org.mozilla.firefox"] {
            #expect(AudioProcesses.parentBundleID(of: bundleID) == bundleID)
        }
    }

    @Test func anAppWhoseNameMerelyContainsHelperIsLeftAlone() {
        // "helper" as a whole component is the signal; a name that happens to contain the letters
        // is not. Truncating here would silence an app the user never named.
        #expect(AudioProcesses.parentBundleID(of: "com.example.helperbee") == "com.example.helperbee")
        #expect(AudioProcesses.parentBundleID(of: "com.helpers.App") == "com.helpers.App")
    }
}
