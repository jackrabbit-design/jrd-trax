import Foundation
import SwiftData

@Model
public final class Allocation {
    @Attribute(.unique) public var id: String
    public var taskId: String
    public var date: Date
    public var scheduledMinutes: Int

    public init(id: String, taskId: String, date: Date, scheduledMinutes: Int) {
        self.id = id
        self.taskId = taskId
        self.date = date
        self.scheduledMinutes = scheduledMinutes
    }
}
