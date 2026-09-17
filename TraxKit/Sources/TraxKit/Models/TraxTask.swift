import Foundation
import SwiftData

@Model
public final class TraxTask {
    @Attribute(.unique) public var id: String
    public var projectId: String
    public var name: String
    public var priority: Priority
    public var dueDate: Date?
    public var statusId: String?
    public var storyId: String
    /// The last-known-server value of `statusId` as of the most recent
    /// successful sync — the baseline used to detect whether `statusId`
    /// changed locally, remotely, or both since then. `nil` means never
    /// synced (no baseline, so no conflict check is possible yet).
    public var syncedStatusId: String?

    public init(
        id: String,
        projectId: String,
        name: String,
        priority: Priority,
        dueDate: Date? = nil,
        statusId: String? = nil,
        storyId: String,
        syncedStatusId: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.priority = priority
        self.dueDate = dueDate
        self.statusId = statusId
        self.storyId = storyId
        self.syncedStatusId = syncedStatusId
    }
}
