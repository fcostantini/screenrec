import Foundation

/// Whether notification banners will appear while the screen is being captured (ADR-022).
///
/// The setting behind it — *"Allow notifications when mirroring or sharing the display"* — has no
/// public API, so this reads a private domain and an undocumented key (docs/07 has the polarity).
/// ⚠️ `unknown` is load-bearing: the key can vanish in any macOS release, and a surface that says the
/// wrong thing confidently is worse than one that hedges.
public enum BannerVisibility: Equatable {

    /// The user allowed banners while sharing — there is nothing to warn about.
    case shown
    /// Banners will be withheld until the capture stops. They still arrive; they don't render.
    case hidden
    /// The setting could not be read, so nothing may be claimed either way.
    case unknown

    /// True for everything except `shown`: an honest surface either states the problem or hedges.
    public var warrantsWarning: Bool { self != .shown }

    private static let domain = "com.apple.ncprefs"
    private static let preferencesKey = "dnd_prefs"
    private static let suppressionKey = "dndMirrored"

    /// Reads the system setting. Cheap enough for a menu that must not wait on anything (M6-T10), and
    /// a change made by System Settings is visible to a long-running app without a relaunch (measured).
    static func current() -> BannerVisibility {
        decoded(from: UserDefaults(suiteName: domain)?.data(forKey: preferencesKey))
    }

    /// Pure, so every branch — including the ones a real machine will not produce on demand — is
    /// asserted without touching the system's preferences.
    static func decoded(from preferences: Data?) -> BannerVisibility {
        guard let preferences,
              let plist = try? PropertyListSerialization.propertyList(
                from: preferences, options: [], format: nil) as? [String: Any],
              let suppressed = plist[suppressionKey] as? Bool
        else { return .unknown }
        // The user's toggle is the inverse of the stored flag: "allow banners while sharing" is
        // `!dndMirrored`, established by flipping it rather than from the name (docs/07).
        return suppressed ? .hidden : .shown
    }
}
