import ScreenCaptureKit

/// A running application the capture engine can scope to (`ContentSelection.app`), decoupled
/// from ScreenCaptureKit so the CLI and app can list apps without importing it.
public struct CapturableApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum CapturableApps {
    /// Apps with on-screen content, name-sorted. Reads the same enumeration the engine resolves
    /// `.app` content against, so a listed app is always one capture can bind. Throws SCK's
    /// "user declined" when Screen Recording is ungranted (docs/02 §1).
    public static func available() async throws -> [CapturableApp] {
        let content = try await SCShareableContent.forCapture()
        return select(content.applications.map { ($0.bundleIdentifier, $0.applicationName) })
    }

    /// Drop unbindable entries (empty bundle ID), dedupe, sort by display name. Pure.
    static func select(_ applications: [(bundleID: String, name: String)]) -> [CapturableApp] {
        var seen = Set<String>()
        return applications
            .compactMap { app -> CapturableApp? in
                guard !app.bundleID.isEmpty, seen.insert(app.bundleID).inserted else { return nil }
                return CapturableApp(bundleID: app.bundleID, name: app.name.isEmpty ? app.bundleID : app.name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
