import Foundation
import SwiftData

public enum PersistenceController {
    public static var schema: Schema {
        Schema([
            Project.self,
            TaskStatus.self,
            TraxTask.self,
            Allocation.self,
            TimeEntry.self,
            RunningTimer.self,
        ])
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
