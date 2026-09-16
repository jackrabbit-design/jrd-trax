import Foundation

/// The app-level, persisted representation of a token — includes
/// `createdAt`, set locally when the token is received, not decoded
/// from the API response.
public struct OAuthToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let tokenType: String
    public let scope: String?
    public let refreshToken: String?
    public let createdAt: Date

    public init(accessToken: String, tokenType: String, scope: String?, refreshToken: String?, createdAt: Date = .now) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
        self.refreshToken = refreshToken
        self.createdAt = createdAt
    }
}

/// The raw token-endpoint response shape, decoded from the wire before
/// being wrapped into an `OAuthToken` with a local `createdAt`.
struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case refreshToken = "refresh_token"
    }
}
