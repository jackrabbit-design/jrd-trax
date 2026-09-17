public struct StatusSetDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let statusIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case statusIds = "status_ids"
    }
}
