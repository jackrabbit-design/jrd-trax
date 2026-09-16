import SwiftUI
import SwiftData
import TraxKit

@main
@MainActor
struct TraxApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try PersistenceController.makeContainer(inMemory: true)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        let context = container.mainContext
        let existingProjectCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        if existingProjectCount == 0 {
            SampleData.seed(into: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(container)
    }
}
