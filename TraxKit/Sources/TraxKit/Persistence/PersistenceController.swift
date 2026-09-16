import Foundation
import SwiftData

@MainActor
public enum PersistenceController {
    public static let schema = Schema([
        Project.self,
        TaskStatus.self,
        TraxTask.self,
        Allocation.self,
        TimeEntry.self,
    ])

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
