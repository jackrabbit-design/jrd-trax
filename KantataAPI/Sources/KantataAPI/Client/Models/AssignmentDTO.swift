public struct AssignmentDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    public let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case workspaceId = "workspace_id"
    }
}
