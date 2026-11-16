import Foundation
import Testing

@testable import UploadCore

/// The sign-in on disk (M40-T2, ADR-024): a file any build can read, replace and delete — which is
/// what the Keychain could not offer a self-signed app — and that nobody else can read.
@Suite struct TokenStoreTests {

    private let token = GoogleToken(
        accessToken: "at", accessTokenExpiry: Date(timeIntervalSince1970: 1_800_000_000),
        refreshToken: "rt", refreshTokenExpiry: Date(timeIntervalSince1970: 1_800_600_000))

    /// A store in a folder of its own, so the folder's permissions are this test's to judge.
    private func makeStore() -> (store: FileTokenStore, url: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("uploadcore-store-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("sign-in.json")
        return (FileTokenStore(url: url), url, folder)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test func aSignInSurvivesSaveReplaceAndDelete() throws {
        let (store, _, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(try store.load() == nil)
        try store.save(token)
        #expect(try store.load() == token)

        var renewed = token
        renewed.accessToken = "newer"
        try store.save(renewed)
        #expect(try store.load() == renewed)

        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }

    /// The whole of what protects it: owner-only on the file and on the folder holding it.
    @Test func onlyItsOwnerCanReadIt() throws {
        let (store, url, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try store.save(token)
        #expect(try permissions(of: url) == 0o600)
        #expect(try permissions(of: folder) == 0o700)
    }

    /// A folder that was already there with looser permissions is tightened, not trusted.
    @Test func anExistingFolderIsTightened() throws {
        let (store, _, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try store.save(token)
        #expect(try permissions(of: folder) == 0o700)
    }

    @Test func savingLeavesNothingBesideTheFile() throws {
        let (store, url, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try store.save(token)
        try store.save(token)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == [url.lastPathComponent])
    }

    /// Unusable is not connected: the caller reconnects, and the next save replaces it.
    @Test func aFileThisBuildCannotDecodeReadsAsNoSignIn() throws {
        let (store, url, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a sign-in".utf8).write(to: url)
        #expect(try store.load() == nil)
        try store.save(token)
        #expect(try store.load() == token)
    }

    @Test func theStandardPlaceIsTheAppsOwnSupportFolder() {
        let url = FileTokenStore.standardURL(named: "youtube-sign-in")
        #expect(url.path.hasSuffix("/Library/Application Support/ScreenRec/youtube-sign-in.json"))
    }

    @Test func aStoreInMemoryForgetsNothingUntilTold() {
        let store = InMemoryTokenStore()
        #expect(store.load() == nil)
        store.save(token)
        #expect(store.load() == token)
        store.delete()
        #expect(store.load() == nil)
    }

    // MARK: - The credentials a build carries

    @Test func aBundleWithoutCredentialsHasNone() {
        #expect(GoogleClientCredentials.bundled(in: Bundle(for: Marker.self)) == nil)
    }
}

private final class Marker {}
