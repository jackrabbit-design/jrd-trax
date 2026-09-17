public struct UserDTO: Codable, Sendable, Equatable {
    public let id: String
    public let fullName: String
    public let email: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
    }
}
