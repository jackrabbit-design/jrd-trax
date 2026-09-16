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
        SampleData.seed(into: container)
    }

    var body: some Scene {
        WindowGroup {
            Text("Trax — \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                .frame(minWidth: 640, minHeight: 480)
        }
        .modelContainer(container)
    }
}
