import CryptoKit
import Foundation

/// A PKCE verifier and its S256 challenge (RFC 7636): what proves that the process redeeming an
/// authorization code is the one that asked for it.
public struct PKCE: Equatable, Sendable {
    public let verifier: String

    /// 32 random bytes, the size RFC 7636 §4.1 recommends.
    public init() {
        verifier = Data.random(count: 32).base64URLEncodedString()
    }

    init(verifier: String) {
        self.verifier = verifier
    }

    public var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    /// From the system generator, which is cryptographically secure on Apple platforms.
    static func random(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// Base64 in the URL-safe alphabet, without padding (RFC 4648 §5).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
