public enum OAuthError: Error, Equatable, Sendable {
    case cancelled
    case accessDenied
    case missingAuthorizationCode
    case stateMismatch
    case listenerFailed(String)
    case exchangeFailed(String)
    case unauthorized
}
