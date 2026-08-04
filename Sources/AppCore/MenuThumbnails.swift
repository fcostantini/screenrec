import AVFoundation
import CoreGraphics
import Foundation
import RecorderCore

/// One frame per recents row (M28-T3), decoded off the main thread and cached until the file
/// changes — the validity rule `RecentRecordings.details(for:cached:)` already uses.
///
/// A file with no readable video (a `.gif`, which AVFoundation cannot open at all) simply never
/// gets one; the row keeps an empty well so the titles stay aligned.
@MainActor
public final class MenuThumbnails {

    /// Where in the clip the frame comes from. The opening frame of a screen recording is usually
    /// an untouched desktop; a little way in is what distinguishes one take from another.
    private static let position = 0.1
    /// Bounds the decoded image: the well is 36 × 22 pt, so this covers a 2× display.
    private static let maxPixels = 80

    private struct Cached {
        let image: CGImage
        let modified: Date
    }

    private var cache: [URL: Cached] = [:]
    private var inFlight: Set<URL> = []

    /// Fires as each frame lands, so a row already on screen can fill itself in — a view-based row
    /// redraws without the menu being rebuilt (docs/07), which is what makes that safe.
    public var onThumbnail: ((URL) -> Void)?

    public init() {}

    public func image(for url: URL) -> CGImage? { cache[url]?.image }

    /// Decodes whatever is missing or stale, and forgets files that are no longer shown.
    public func prime(_ urls: [URL]) {
        let shown = Set(urls)
        cache = cache.filter { shown.contains($0.key) }

        for url in urls where !inFlight.contains(url) {
            let modified = url.freshResourceValues(forKeys: [.contentModificationDateKey])?
                .contentModificationDate ?? .distantPast
            guard cache[url]?.modified != modified else { continue }
            inFlight.insert(url)
            Task { await decode(url, modified: modified) }
        }
    }

    private func decode(_ url: URL, modified: Date) async {
        defer { inFlight.remove(url) }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds,
              duration > 0, duration.isFinite
        else { return }

        let times = [duration * Self.position]
        for await frame in FilmstripThumbnails.stream(
            for: asset, times: times, maxPixels: Self.maxPixels) {
            cache[url] = Cached(image: frame.image, modified: modified)
            onThumbnail?(url)
            break
        }
    }
}
