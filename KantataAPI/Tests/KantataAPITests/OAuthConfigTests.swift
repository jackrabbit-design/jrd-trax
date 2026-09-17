import Testing
import Foundation
@testable import KantataAPI

@Suite("OAuth config")
struct OAuthConfigTests {
    @Test("redirect URI uses the configured fixed loopback port")
    func redirectURI() {
        let config = OAuthConfig(clientID: "abc", redirectPort: 51818)
        #expect(config.redirectURI.absoluteString == "http://127.0.0.1:51818/callback")
    }

    @Test("authorization URL includes all required query parameters")
    func authorizationURLQueryItems() {
        let config = OAuthConfig(clientID: "my-client-id", redirectPort: 51818, scope: "read write")
        let pkce = PKCE()
        let url = config.makeAuthorizationURL(pkce: pkce, state: "test-state")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(items["client_id"] == "my-client-id")
        #expect(items["redirect_uri"] == "http://127.0.0.1:51818/callback")
        #expect(items["response_type"] == "code")
        #expect(items["state"] == "test-state")
        #expect(items["code_challenge"] == pkce.codeChallenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["scope"] == "read write")
    }

    @Test("scope is omitted from the URL when nil")
    func noScopeWhenNil() {
        let config = OAuthConfig(clientID: "abc", redirectPort: 51818, scope: nil)
        let url = config.makeAuthorizationURL(pkce: PKCE(), state: "s")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(!(components.queryItems ?? []).contains { $0.name == "scope" })
    }
}
