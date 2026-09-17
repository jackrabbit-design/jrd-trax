import Foundation

public final class LoopbackOAuthClient: OAuthClient, @unchecked Sendable {
    private let config: OAuthConfig
    private let transport: any HTTPTransport
    private let makeListener: @Sendable () -> any CallbackListening
    private let openBrowser: @Sendable (URL) -> Void
    private var activeListener: (any CallbackListening)?
    private let lock = NSLock()

    public init(
        config: OAuthConfig,
        transport: any HTTPTransport,
        makeListener: @escaping @Sendable () -> any CallbackListening,
        openBrowser: @escaping @Sendable (URL) -> Void
    ) {
        self.config = config
        self.transport = transport
        self.makeListener = makeListener
        self.openBrowser = openBrowser
    }

    public func signIn() async throws -> OAuthToken {
        let pkce = PKCE()
        let state = UUID().uuidString
        let listener = makeListener()
        lock.withLock { activeListener = listener }
        defer {
            listener.stop()
            lock.withLock { activeListener = nil }
        }

        _ = try await listener.start()
        let authURL = config.makeAuthorizationURL(pkce: pkce, state: state)
        openBrowser(authURL)

        let params: [String: String]
        do {
            params = try await listener.waitForCallback()
        } catch is CancellationError {
            throw OAuthError.cancelled
        }

        if let errorParam = params["error"] {
            throw errorParam == "access_denied" ? OAuthError.accessDenied : OAuthError.exchangeFailed(errorParam)
        }
        guard let code = params["code"] else {
            throw OAuthError.missingAuthorizationCode
        }
        guard let returnedState = params["state"], returnedState == state else {
            throw OAuthError.stateMismatch
        }

        return try await exchange(code: code, pkce: pkce)
    }

    public func cancel() {
        let listener = lock.withLock { () -> (any CallbackListening)? in
            let listener = activeListener
            activeListener = nil
            return listener
        }
        listener?.stop()
    }

    private func exchange(code: String, pkce: PKCE) async throws -> OAuthToken {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "client_secret", value: config.clientSecret),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: pkce.codeVerifier),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw OAuthError.exchangeFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OAuthError.exchangeFailed("HTTP \(http.statusCode)")
        }
        do {
            let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            return OAuthToken(accessToken: decoded.accessToken, tokenType: decoded.tokenType, scope: decoded.scope, refreshToken: decoded.refreshToken)
        } catch {
            throw OAuthError.exchangeFailed("Could not decode token response")
        }
    }
}
