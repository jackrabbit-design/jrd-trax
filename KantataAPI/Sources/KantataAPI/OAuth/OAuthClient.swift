public protocol OAuthClient: Sendable {
    func signIn() async throws -> OAuthToken
    func cancel()
}
