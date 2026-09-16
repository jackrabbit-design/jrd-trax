import SwiftUI
import SwiftData
import AppKit
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
                .onAppear {
                    // Running as a bare executable (no .app bundle) means
                    // the process doesn't automatically get Dock/window
                    // focus — without this, the window can open off-screen
                    // or simply never come forward.
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(container)
    }
}
