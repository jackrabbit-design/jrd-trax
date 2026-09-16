import Foundation
import SwiftData

/// Singleton row (id is always "current") representing the one timer that
/// can be running at a time. Starting a new timer deletes this row first;
/// that invariant is enforced by the app layer, not the schema.
@Model
public final class RunningTimer {
    @Attribute(.unique) public var id: String
    public var taskId: String
    public var startedAt: Date

    public init(id: String = "current", taskId: String, startedAt: Date = .now) {
        self.id = id
        self.taskId = taskId
        self.startedAt = startedAt
    }
}
