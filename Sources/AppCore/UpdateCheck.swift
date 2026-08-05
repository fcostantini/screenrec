import Foundation
import RecorderCore
import os

/// Whether a newer release exists (M32, ADR-020). **Reads, never writes**: nothing about the user,
/// the machine or any recording leaves here, nothing is downloaded, and a check that fails is
/// silent — a build that can't reach GitHub behaves exactly like one that is current.
public enum UpdateCheck {

    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "update")

    /// How long before a still-running app looks again (Franco, 2026-08-05). Launch-only was the
    /// first shape and is the wrong one: this app is an `LSUIElement` that sits in the menu bar for
    /// days — Franco's own instance ran **18 h+ without a relaunch** — so the machine most likely to
    /// be behind is the one least likely to check.
    public static let recheckInterval: Duration = .seconds(24 * 60 * 60)

    /// The releases ADR-014 hands people a build from — the same list a recipient is sent to.
    /// ⚠️ Readable only because the repo is public (ADR-021); unauthenticated it 404s on a private
    /// one, which is what blocked this task until Franco made the repo public.
    static let releasesURL = URL(
        string: "https://api.github.com/repos/fcostantini/screenrec/releases")!

    /// The same list as a page a person can read — where the update row sends them. Distinct from
    /// `releasesURL`, which answers JSON; ADR-020 forbids downloading, not linking, and this is the
    /// manual path ADR-014 documents.
    public static let releasesPageURL = URL(
        string: "https://github.com/fcostantini/screenrec/releases")!

    /// A tag as orderable integers, or nil when it isn't three of them.
    ///
    /// A leading `v` is optional because the repo's tags carry one and `VERSION` does not. Anything
    /// else — a pre-release suffix, a date tag, a word — returns nil and is **ignored rather than
    /// guessed at**: ordering a tag we don't understand is how a build talks itself into "you're out
    /// of date" against something that isn't a release.
    static func components(_ tag: String) -> [Int]? {
        let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers
    }

    /// The newest tag in `tags` that is strictly newer than `current`, or nil when none is —
    /// including when `current` itself is unparseable, where saying nothing beats saying something
    /// wrong.
    ///
    /// Pure, so every ordering case is asserted without a network: the live half can only ever be
    /// smoke-tested.
    public static func newestRelease(among tags: [String], laterThan current: String) -> String? {
        guard let mine = components(current) else { return nil }
        return tags
            .compactMap { tag in components(tag).map { (tag: tag, parts: $0) } }
            .filter { isAscending(mine, $0.parts) }
            .max { isAscending($0.parts, $1.parts) }?
            .tag
    }

    private static func isAscending(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for (l, r) in zip(lhs, rhs) where l != r { return l < r }
        return false
    }

    /// Reads the release list and returns its tags, or an empty list on any failure. Never throws
    /// and never blocks a caller that doesn't await it — ADR-020's "silent when it fails".
    ///
    /// Unauthenticated, so GitHub rate-limits by IP at 60/hour; one check per launch is nothing
    /// against that. ⚠️ **The one privacy cost, and it is real:** this tells `github.com` the
    /// machine's IP address (ADR-020).
    public static func fetchTags() async -> [String] {
        var request = URLRequest(url: releasesURL)
        request.timeoutInterval = 10          // a slow answer must never be a slow launch
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                log.info("update check: unexpected response")
                return []
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            return releases.filter { !$0.draft && !$0.prerelease }.map(\.tagName)
        } catch {
            // Offline, rate-limited, or a shape we don't recognise — all the same outcome.
            log.info("update check: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }
}
