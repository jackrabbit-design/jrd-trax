import Foundation

public struct OAuthConfig: Sendable {
    public let clientID: String
    /// Kantata's OAuth token endpoint requires a confidential-client secret
    /// on the code exchange (confirmed against developer.kantata.com — it
    /// does not support a PKCE-only public client, contrary to this app's
    /// original assumption). PKCE is still included on top of it as
    /// defense-in-depth, but the secret is what Kantata actually requires.
    public let clientSecret: String
    public let redirectPort: UInt16
    public let authorizeURL: URL
    public let tokenURL: URL
    public let scope: String?

    public init(
        clientID: String,
        clientSecret: String,
        redirectPort: UInt16 = 51818,
        authorizeURL: URL = URL(string: "https://app.mavenlink.com/oauth/authorize")!,
        tokenURL: URL = URL(string: "https://app.mavenlink.com/oauth/token")!,
        scope: String? = nil
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
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
