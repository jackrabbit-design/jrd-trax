public struct DailyScheduledHourDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    /// Kept as the raw wire string (e.g. "2026-09-16") — date parsing
    /// into a real `Date` happens at the mapping layer, not here.
    public let date: String
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case date, hours
    }
}
