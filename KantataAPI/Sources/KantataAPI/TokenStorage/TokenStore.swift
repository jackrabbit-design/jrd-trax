import Security

public protocol TokenStore: Sendable {
    func save(_ token: OAuthToken) throws
    func load() throws -> OAuthToken?
    func delete() throws
}

public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
}
