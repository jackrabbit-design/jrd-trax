public struct TimeEntryDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    public let date: String
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case date, hours
    }
}

public struct TimeEntryCreateRequest: Encodable, Sendable, Equatable {
    public let storyId: String
    public let date: String
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case storyId = "story_id"
        case date, hours
    }

    public init(storyId: String, date: String, hours: Double) {
        self.storyId = storyId
        self.date = date
        self.hours = hours
    }
}
