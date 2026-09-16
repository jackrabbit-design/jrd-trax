import Foundation
import SwiftData

/// Invariant: there should be exactly one `Allocation` row per `(taskId, date)`
/// pair. This is **not enforced at the schema level** — SwiftData's
/// `@Attribute(.unique)` only supports single-property uniqueness at this
/// deployment target (macOS 14); compound uniqueness via `#Unique<T>`
/// requires macOS 15+. Until the sync layer (a future sub-project) exists,
/// callers must upsert by `(taskId, date)` rather than blindly inserting, to
/// avoid duplicate rows. Note also that if a Kantata allocation's own ID
/// changes, that would currently produce a duplicate row rather than an
/// update in-place — this is a known limitation for the sync layer to handle.
@Model
public final class Allocation {
    @Attribute(.unique) public var id: String
    public var taskId: String
    /// Day-granularity: normalized to the start of the calendar day in the
    /// user's local timezone (`Calendar.current`) by the initializer.
    public var date: Date
    public var scheduledMinutes: Int

    public init(id: String, taskId: String, date: Date, scheduledMinutes: Int) {
        self.id = id
        self.taskId = taskId
        self.date = Calendar.current.startOfDay(for: date)
        self.scheduledMinutes = scheduledMinutes
    }
}
