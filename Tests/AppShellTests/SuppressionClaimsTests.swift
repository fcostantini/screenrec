import Foundation
import Testing

@testable import AppCore
@testable import AppShell

/// Every user-visible claim about banner suppression must come from a file that actually **reads**
/// whether banners are suppressed (M36-T1, ADR-022).
///
/// 🔴 This exists because of how M35 went wrong: docs/06 recorded M12-T5 as "three touches", M35 fixed
/// those three, and G35's "every surface" criterion was checked against that **enumeration** rather
/// than against the source. A fourth surface asserted suppression unconditionally for a day.
///
/// ⚠️ **Its honest limit:** it recognises the phrasings we use today. Someone inventing new words for
/// the same claim slips past. It guards against **drift** — a new copy of known wording landing in a
/// file that never consults the setting — not against creativity.
@Suite struct SuppressionClaimsTests {

    /// Wordings that assert or hedge about banners being withheld.
    private static let claims = [
        "hides notification", "hide notification", "hides banners", "hide banners",
        "banners are hidden", "may be hidden", "hidden while armed",
    ]

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // AppShellTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
    }

    private static func sourceFiles() throws -> [URL] {
        let sources = repoRoot().appendingPathComponent("Sources")
        let all = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        return (all?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
    }

    /// A line that shows a claim to a user: it carries a string literal, and it isn't a comment about
    /// the feature. Doc comments discussing suppression are prose, not copy.
    private static func claimingLines(in contents: String) -> [String] {
        contents.split(separator: "\n").map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), trimmed.contains("\"") else { return false }
            return claims.contains { trimmed.localizedCaseInsensitiveContains($0) }
        }
    }

    @Test func everySuppressionClaimComesFromAFileThatReadsTheSetting() throws {
        var offenders: [String] = []
        for file in try Self.sourceFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            guard !Self.claimingLines(in: contents).isEmpty else { continue }
            // Case-insensitive on purpose: a consumer may name the type (`BannerVisibility`) or only
            // the property it reads it through (`state.bannerVisibility()`), as `MenuBuilder` does.
            guard !contents.localizedCaseInsensitiveContains("bannervisibility") else { continue }
            offenders.append(file.lastPathComponent)
        }
        #expect(
            offenders.isEmpty,
            "these files tell the user about banner suppression without reading it: \(offenders)")
    }

    /// The guard is only worth having if it can see a claim at all — so prove it recognises one rather
    /// than passing because the matcher is broken.
    @Test func theGuardRecognisesAClaim() {
        let planted = """
                Text("While replay is armed, macOS hides notification banners.")
            """
        #expect(!Self.claimingLines(in: planted).isEmpty)
        // …and ignores prose about the same thing.
        let prose = "    /// Whether the one-time \"banners are hidden while armed\" alert has been shown."
        #expect(Self.claimingLines(in: prose).isEmpty)
    }

    // MARK: - The caption itself

    @Test func theCaptionStatesWhatTheAppCanTell() {
        #expect(ArmedBannerCaption.text(for: .hidden).contains("macOS hides notification banners"))
        #expect(!ArmedBannerCaption.text(for: .hidden).contains("may hide"))

        #expect(ArmedBannerCaption.text(for: .shown).contains("keep working while replay is armed"))
        #expect(!ArmedBannerCaption.text(for: .shown).contains("hides"))

        // The hedge survives exactly one state, and it is the one the app cannot see.
        #expect(ArmedBannerCaption.text(for: .unknown).contains("may hide notification banners"))
    }

    /// The two states that need fixing name the setting exactly, because the pane is where someone
    /// goes to change it. ⚠️ `shown` deliberately does **not**: there is no fix left to name, and
    /// docs/06's rule is to name the fix rather than recite the API.
    @Test func theStatesThatNeedAFixNameItExactly() {
        for banners in [BannerVisibility.hidden, .unknown] {
            #expect(
                ArmedBannerCaption.text(for: banners).contains(
                    "\"Allow notifications when mirroring or sharing the display\""),
                "\(banners) should name the setting exactly as System Settings spells it")
        }
        #expect(!ArmedBannerCaption.text(for: .shown).contains("turn on"))
    }
}
