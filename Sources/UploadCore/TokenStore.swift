import Foundation

public protocol TokenStore: Sendable {
    func load() throws -> GoogleToken?
    func save(_ token: GoogleToken) throws
    func delete() throws
}

/// The sign-in as one file only its owner can read (ADR-024). Not the Keychain: with a signing
/// identity that has no team ID, an item there belongs to the build that made it (07) — a rebuilt
/// app is asked for the login password, and cannot delete what it finds.
public struct FileTokenStore: TokenStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/ScreenRec/<name>.json`. Each program keeps its own `name`,
    /// so the CLI can never disconnect the app.
    public static func standardURL(named name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScreenRec/\(name).json")
    }

    public func load() throws -> GoogleToken? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        // A file this build cannot decode is a sign-in it cannot use; the caller reconnects.
        return try? JSONDecoder().decode(GoogleToken.self, from: data)
    }

    /// Written beside the file with its final permissions and renamed over it: the token is never
    /// on disk readable by anyone else, and a crash mid-write leaves the old sign-in whole.
    public func save(_ token: GoogleToken) throws {
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard files.createFile(
            atPath: temporary.path, contents: try JSONEncoder().encode(token),
            attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temporary.path, url.path) == 0 else {
            let failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? files.removeItem(at: temporary)
            throw failure
        }
    }

    public func delete() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }
}

/// A sign-in that lives only as long as the process — what an app with no account storage holds,
/// and what tests hand in.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: GoogleToken?

    public init(_ token: GoogleToken? = nil) {
        self.token = token
    }

    public func load() -> GoogleToken? { lock.withLock { token } }
    public func save(_ token: GoogleToken) { lock.withLock { self.token = token } }
    public func delete() { lock.withLock { token = nil } }
}
