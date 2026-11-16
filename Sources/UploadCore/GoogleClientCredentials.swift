import Foundation

/// The OAuth client a build signs in to Google with (ADR-024): the `installed` object of the JSON
/// the Cloud console downloads for a **Desktop** client.
public struct GoogleClientCredentials: Equatable, Sendable {
    public let clientID: String
    /// The token endpoint refuses a Desktop client without it, PKCE or not (07). Not confidential:
    /// Google's docs say an installed app's secret "is obviously not treated as a secret".
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Where a developer's credentials live — outside the tree, so they cannot be committed.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/screenrec/youtube-client.json")
    }

    public init(contentsOf url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            throw GoogleClientCredentialsError.missing(url)
        } catch {
            throw GoogleClientCredentialsError.cannotRead(url, reason: error.localizedDescription)
        }
        try self.init(json: data)
    }

    public init(json data: Data) throws {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            throw GoogleClientCredentialsError.unreadable
        }
        guard let client = file.installed else {
            throw GoogleClientCredentialsError.notADesktopClient
        }
        self.init(clientID: client.clientID, clientSecret: client.clientSecret)
    }

    private struct File: Decodable {
        let installed: Client?
    }

    private struct Client: Decodable {
        let clientID: String
        let clientSecret: String
        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
        }
    }
}

public enum GoogleClientCredentialsError: Error, Equatable {
    case missing(URL)
    /// The file is there and could not be read — permissions, or not a file at all.
    case cannotRead(URL, reason: String)
    /// Read, but not the JSON the Cloud console downloads.
    case unreadable
    /// The file is for another client type (`web`), which cannot take a loopback redirect.
    case notADesktopClient
}
