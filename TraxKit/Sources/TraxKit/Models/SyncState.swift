import Foundation
import SwiftData

/// Singleton row (id is always "current") tracking when the last
/// successful sync completed. Enforced at the app layer, not the schema,
/// same pattern as `RunningTimer`.
@Model
public final class SyncState {
    @Attribute(.unique) public var id: String
    public var lastSyncedAt: Date?

    public init(id: String = "current", lastSyncedAt: Date? = nil) {
        self.id = id
        self.lastSyncedAt = lastSyncedAt
    }
}
