import Foundation
import SwiftData

@Model
public final class TimeEntry {
    @Attribute(.unique) public var id: String
    public var taskId: String
    /// Day-granularity: normalized to the start of the calendar day in the
    /// user's local timezone (`Calendar.current`) by the initializer.
    public var date: Date
    public var minutes: Int
    public var synced: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        date: Date,
        minutes: Int,
        synced: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.taskId = taskId
        self.date = Calendar.current.startOfDay(for: date)
        self.minutes = minutes
        self.synced = synced
        self.createdAt = createdAt
    }
}
