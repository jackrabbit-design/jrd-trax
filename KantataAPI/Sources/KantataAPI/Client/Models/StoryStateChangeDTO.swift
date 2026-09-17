public struct StoryStateChangeDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    public let statusId: String

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case statusId = "status_id"
    }
}

public struct StoryStateChangeCreateRequest: Encodable, Sendable, Equatable {
    public let storyId: String
    public let statusId: String

    enum CodingKeys: String, CodingKey {
        case storyId = "story_id"
        case statusId = "status_id"
    }

    public init(storyId: String, statusId: String) {
        self.storyId = storyId
        self.statusId = statusId
    }
}
