public struct StoryDTO: Codable, Sendable, Equatable {
    public let id: String
    public let workspaceId: String
    public let title: String
    public let priority: String?
    public let dueDate: String?
    public let statusId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case title, priority
        case dueDate = "due_date"
        case statusId = "status_id"
    }
}
