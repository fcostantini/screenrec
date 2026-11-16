import Foundation
import Testing

@testable import UploadCore

/// Writes to the real login Keychain, so it runs only on request: `SCREENREC_KEYCHAIN_TESTS=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_KEYCHAIN_TESTS"] == "1"))
struct KeychainTokenStoreTests {

    @Test func aSignInSurvivesSaveUpdateAndDelete() throws {
        let store = KeychainTokenStore(service: "dev.fcostantini.screenrec.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        var token = GoogleToken(
            accessToken: "at", accessTokenExpiry: expiry, refreshToken: "rt",
            refreshTokenExpiry: expiry.addingTimeInterval(600_000))

        #expect(try store.load() == nil)
        try store.save(token)
        #expect(try store.load() == token)

        token.accessToken = "newer"
        try store.save(token)
        #expect(try store.load() == token)

        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }
}
