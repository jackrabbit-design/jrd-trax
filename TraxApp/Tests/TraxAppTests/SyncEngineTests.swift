import Testing
import Foundation
import SwiftData
import TraxKit
import KantataAPI
@testable import TraxApp

final class RoutingStubTransport: HTTPTransport, @unchecked Sendable {
    var responsesByPath: [String: String] = [:]
    var failingPaths: Set<String> = []
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url?.lastPathComponent ?? ""
        if failingPaths.contains(path) {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        let json = responsesByPath[path] ?? "[]"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }
}

@Suite("Sync engine")
@MainActor
struct SyncEngineTests {
    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    private func makeEngine(context: ModelContext, transport: RoutingStubTransport) -> SyncEngine {
        let apiClient = KantataAPIClient(transport: transport, tokenProvider: { "tok" })
        return SyncEngine(modelContext: context, apiClient: apiClient)
    }

    @Test("prepareSync with no local tasks returns no conflicts")
    func prepareSyncNoLocalTasks() async throws {
        let context = try makeContext()
        let transport = RoutingStubTransport()
        let engine = makeEngine(context: context, transport: transport)

        let preparation = try await engine.prepareSync()

        #expect(preparation.conflicts.isEmpty)
    }

    @Test("prepareSync detects a real status conflict")
    func prepareSyncDetectsConflict() async throws {
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
        let engine = makeEngine(context: context, transport: transport)

        let preparation = try await engine.prepareSync()

        #expect(preparation.conflicts.count == 1)
        #expect(preparation.conflicts.first?.localStatusId == "s2")
        #expect(preparation.conflicts.first?.remoteStatusId == "s3")
    }

    @Test("applySync pushes unsynced time entries and marks them synced")
    func applySyncPushesTimeEntries() async throws {
        let context = try makeContext()
        let entry = TimeEntry(taskId: "st1", date: Date(timeIntervalSince1970: 0), minutes: 90)
        context.insert(entry)
        try context.save()

        let transport = RoutingStubTransport()
        transport.responsesByPath["time_entries"] = #"{"id":"te1","story_id":"st1","date":"1970-01-01","hours":1.5}"#
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()

        try await engine.applySync(preparation, resolutions: [:])

        #expect(entry.synced == true)
        #expect(transport.requests.contains { $0.url?.lastPathComponent == "time_entries" && $0.httpMethod == "POST" })
    }

    @Test("applySync pushes a local status change when only local changed")
    func applySyncPushesStatusChange() async throws {
        let context = try makeContext()
        let task = TraxTask(
            id: "st1", projectId: "w1", name: "Design homepage",
            priority: .normal, statusId: "s2", storyId: "st1", syncedStatusId: "s1"
        )
        context.insert(task)
        try context.save()

        let transport = RoutingStubTransport()
        transport.responsesByPath["task_statuses"] = #"[{"id":"s1","name":"To Do"},{"id":"s2","name":"In Progress"}]"#
        transport.responsesByPath["stories"] = #"[{"id":"st1","workspace_id":"w1","title":"Design homepage","status_id":"s1"}]"#
        transport.responsesByPath["story_state_changes"] = #"{"id":"c1","story_id":"st1","status_id":"s2"}"#
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()
        #expect(preparation.conflicts.isEmpty)

        try await engine.applySync(preparation, resolutions: [:])

        #expect(transport.requests.contains { $0.url?.lastPathComponent == "story_state_changes" })
        #expect(task.syncedStatusId == "s2")
    }

    @Test("applySync applies useKantatas by overwriting the local status")
    func applySyncUseKantatasOverwritesLocal() async throws {
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
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()
        #expect(preparation.conflicts.count == 1)

        try await engine.applySync(preparation, resolutions: ["st1": .useKantatas])

        #expect(task.statusId == "s3")
        #expect(task.syncedStatusId == "s3")
        #expect(!transport.requests.contains { $0.url?.lastPathComponent == "story_state_changes" })
    }

    @Test("applySync throws missingResolution if a conflict was not resolved")
    func applySyncThrowsOnMissingResolution() async throws {
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
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()

        await #expect(throws: SyncError.missingResolution("st1")) {
            try await engine.applySync(preparation, resolutions: [:])
        }
    }

    @Test("applySync pulls a newly-assigned task")
    func applySyncPullsNewTask() async throws {
        let context = try makeContext()
        let transport = RoutingStubTransport()
        transport.responsesByPath["assignments"] = #"[{"id":"a1","story_id":"st9","workspace_id":"w1"}]"#
        transport.responsesByPath["stories"] = #"[{"id":"st9","workspace_id":"w1","title":"New task","status_id":"s1"}]"#
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()

        try await engine.applySync(preparation, resolutions: [:])

        let tasks = try context.fetch(FetchDescriptor<TraxTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.name == "New task")
        #expect(tasks.first?.syncedStatusId == "s1")
    }

    @Test("applySync updates lastSyncedAt")
    func applySyncUpdatesLastSyncedAt() async throws {
        let context = try makeContext()
        let transport = RoutingStubTransport()
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()

        try await engine.applySync(preparation, resolutions: [:])

        let states = try context.fetch(FetchDescriptor<SyncState>())
        #expect(states.first?.lastSyncedAt != nil)
    }

    @Test("applySync reports a partial failure without losing successful pushes")
    func applySyncReportsPartialFailure() async throws {
        let context = try makeContext()
        let entry = TimeEntry(taskId: "st1", date: Date(timeIntervalSince1970: 0), minutes: 30)
        context.insert(entry)
        try context.save()

        let transport = RoutingStubTransport()
        transport.failingPaths = ["time_entries"]
        let engine = makeEngine(context: context, transport: transport)
        let preparation = try await engine.prepareSync()

        await #expect(throws: SyncError.self) {
            try await engine.applySync(preparation, resolutions: [:])
        }
        #expect(entry.synced == false)
    }
}
