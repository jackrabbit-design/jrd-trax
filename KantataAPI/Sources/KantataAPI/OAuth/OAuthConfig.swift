import Foundation

public struct OAuthConfig: Sendable {
    public let clientID: String
    public let redirectPort: UInt16
    public let authorizeURL: URL
    public let tokenURL: URL
    public let scope: String?

    public init(
        clientID: String,
        redirectPort: UInt16 = 51818,
        authorizeURL: URL = URL(string: "https://app.mavenlink.com/oauth/authorize")!,
        tokenURL: URL = URL(string: "https://app.mavenlink.com/oauth/token")!,
        scope: String? = nil
    ) {
        self.clientID = clientID
        self.redirectPort = redirectPort
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.scope = scope
    }

    public var redirectURI: URL {
        URL(string: "http://127.0.0.1:\(redirectPort)/callback")!
    }

    public func makeAuthorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod),
        ]
        if let scope {
            items.append(URLQueryItem(name: "scope", value: scope))
        }
        components.queryItems = items
        return components.url!
    }
}
