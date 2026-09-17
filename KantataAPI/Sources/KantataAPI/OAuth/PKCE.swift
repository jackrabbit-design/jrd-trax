import Foundation
import CryptoKit

public struct PKCE: Sendable, Equatable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String = "S256"

    public init() {
        self.codeVerifier = Self.makeCodeVerifier()
        self.codeChallenge = Self.challenge(forVerifier: codeVerifier)
    }

    static func makeCodeVerifier(length: Int = 64) -> String {
        let allowed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in allowed.randomElement()! })
    }

    static func challenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
