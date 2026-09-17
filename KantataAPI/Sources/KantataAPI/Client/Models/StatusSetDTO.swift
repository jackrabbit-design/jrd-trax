public struct StatusSetDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let workspaceId: String
    public let statusIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case workspaceId = "workspace_id"
        case statusIds = "status_ids"
    }
}
