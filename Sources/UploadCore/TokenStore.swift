import Foundation
import Security

public protocol TokenStore: Sendable {
    func load() throws -> GoogleToken?
    func save(_ token: GoogleToken) throws
    func delete() throws
}

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

/// The sign-in as one generic-password item in the login Keychain. An item belongs to the program
/// that made it, so each signed program keeps its own under its own `service`.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private static let account = "google"

    public init(service: String) {
        self.service = service
    }

    private var item: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.account,
        ]
    }

    public func load() throws -> GoogleToken? {
        var query = item
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = found as? Data else {
            throw KeychainError.status(status)
        }
        // An item this build cannot decode is a sign-in it cannot use; the caller reconnects.
        return try? JSONDecoder().decode(GoogleToken.self, from: data)
    }

    public func save(_ token: GoogleToken) throws {
        let data = try JSONEncoder().encode(token)
        let updated = SecItemUpdate(item as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard updated == errSecItemNotFound else {
            guard updated == errSecSuccess else { throw KeychainError.status(updated) }
            return
        }
        var attributes = item
        attributes[kSecValueData] = data
        attributes[kSecAttrLabel] = "ScreenRec YouTube sign-in"
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.status(added) }
    }

    public func delete() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
