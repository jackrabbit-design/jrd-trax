public enum KantataAPIError: Error, Sendable {
    case unauthorized
    case httpError(Int)
    case decodingFailed(Error)
}

extension KantataAPIError: Equatable {
    public static func == (lhs: KantataAPIError, rhs: KantataAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized):
            return true
        case let (.httpError(a), .httpError(b)):
            return a == b
        case (.decodingFailed, .decodingFailed):
            return true
        default:
            return false
        }
    }
}
