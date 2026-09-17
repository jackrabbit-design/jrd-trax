import Testing
import Foundation
import SwiftData
import TraxKit
import KantataAPI
@testable import TraxApp

@Suite("Sync controller")
@MainActor
struct SyncControllerTests {
    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("a sync with no conflicts completes and returns to idle")
    func noConflictsCompletesSync() async throws {
        let context = try makeContext()
        let transport = RoutingStubTransport()
        let engine = SyncEngine(modelContext: context, apiClient: KantataAPIClient(transport: transport, tokenProvider: { "tok" }))
        let controller = SyncController(engine: engine)

        await controller.startSync()

        #expect(controller.phase == .idle)
    }

    @Test("conflicts pause the controller until resolved")
    func conflictsPauseThenResolve() async throws {
        let context = try makeContext()
        let task = TraxTask(
            id: "st1", projectId: "w1", name: "Design homepage",
            priority: .normal, statusId: "s2", storyId: "st1", syncedStatusId: "s1"
        )
        context.insert(task)
        try context.save()

        let transport = RoutingStubTransport()
        transport.responsesByPath["task_statuses"] = #"[{"id":"s1","name":"To Do"},{"id":"s2","name":"In Progress"},{"id":"s3","name":"Done"}]"#
        transport.responsesByPath["stories"] = #"[{"id":"st1","workspace_id":"w1","title":"Design homepage","status_id":"s3"}]"#
        transport.responsesByPath["story_state_changes"] = #"{"id":"c1","story_id":"st1","status_id":"s2"}"#
        let engine = SyncEngine(modelContext: context, apiClient: KantataAPIClient(transport: transport, tokenProvider: { "tok" }))
        let controller = SyncController(engine: engine)

        await controller.startSync()

        guard case .conflicts(let conflicts) = controller.phase else {
            Issue.record("expected .conflicts, got \(controller.phase)")
            return
        }
        #expect(conflicts.count == 1)

        await controller.resolveConflicts(["st1": .keepMine])

        #expect(controller.phase == .idle)
    }

    @Test("a fetch failure surfaces as .failed")
    func fetchFailureSurfacesAsFailed() async throws {
        let context = try makeContext()
        let transport = RoutingStubTransport()
        transport.failingPaths = ["task_statuses"]
        let engine = SyncEngine(modelContext: context, apiClient: KantataAPIClient(transport: transport, tokenProvider: { "tok" }))
        let controller = SyncController(engine: engine)

        await controller.startSync()

        guard case .failed = controller.phase else {
            Issue.record("expected .failed, got \(controller.phase)")
            return
        }
    }

    @Test("cancelConflicts discards the pending preparation and returns to idle")
    func cancelConflictsReturnsToIdle() async throws {
        let context = try makeContext()
        let task = TraxTask(
            id: "st1", projectId: "w1", name: "Design homepage",
            priority: .normal, statusId: "s2", storyId: "st1", syncedStatusId: "s1"
        )
        context.insert(task)
        try context.save()

        let transport = RoutingStubTransport()
        transport.responsesByPath["task_statuses"] = #"[{"id":"s1","name":"To Do"},{"id":"s2","name":"In Progress"},{"id":"s3","name":"Done"}]"#
        transport.responsesByPath["stories"] = #"[{"id":"st1","workspace_id":"w1","title":"Design homepage","status_id":"s3"}]"#
        let engine = SyncEngine(modelContext: context, apiClient: KantataAPIClient(transport: transport, tokenProvider: { "tok" }))
        let controller = SyncController(engine: engine)
        await controller.startSync()

        controller.cancelConflicts()

        #expect(controller.phase == .idle)
    }
}
