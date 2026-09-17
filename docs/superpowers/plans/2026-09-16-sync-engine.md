# Sync Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement manual push/pull sync with per-field (status-only) conflict resolution, the sync-in-progress overlay, the staleness banner, and the failure toast — wiring real Kantata data into the app for the first time.

**Architecture:** Small additive changes to `TraxKit` (a sync baseline field + a singleton `SyncState` model) and `KantataAPI` (a bounded date range on the allocations fetch, plus a push method for status changes). The orchestration itself is new `TraxApp` code with a deliberate two-phase split — `SyncEngine.prepareSync()` (read-only: fetch remote snapshot, detect conflicts) and `SyncEngine.applySync(resolutions:)` (push/pull/mutate) — so conflict resolution can pause the flow without the engine managing its own suspended continuation. `SyncController` is a thin `@Observable` state machine wrapping the engine for the UI. Every external call (`KantataAPIClient`) goes through the same stub-transport testing pattern established in sub-project #3.

**Tech Stack:** Swift 6 toolchain, macOS 14+ deployment target, SwiftData, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-16-sync-engine-design.md` (and top-level `SPEC.md` § Sync for the behavior this implements)

## Global Constraints

- macOS 14+ deployment target, matching the rest of the app.
- Swift Testing, not XCTest.
- Conflict resolution applies to the `status` field only — scheduled time and logged time have no local edit path and therefore no conflict scenario (see the design doc's Decisions section). Do not build conflict handling for those.
- An `unauthorized` error during sync surfaces as a plain failure (toast + Retry), not an automatic return to the first-launch screen.
- A task no longer present in a pulled Assignments list is left alone locally, never deleted, to avoid orphaning its `TimeEntry` history.
- A pull never overwrites a task's `statusId` for a task that already exists locally — that field is conflict-managed, refreshed only via the conflict-resolution/push path. Only `name`, `priority`, and `dueDate` are refreshed on pull for existing tasks.
- No automatic/interval sync — every sync is user-triggered.
- No token refresh flow (unchanged from sub-project #3).

---

### Task 1: TraxKit additions — sync baseline field and `SyncState` (TDD)

**Files:**
- Modify: `TraxKit/Sources/TraxKit/Models/TraxTask.swift`
- Create: `TraxKit/Sources/TraxKit/Models/SyncState.swift`
- Modify: `TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift`
- Modify: `TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift`

**Interfaces:**
- Produces: `TraxTask.syncedStatusId: String?` (new field, defaults to `nil`), `SyncState(id: String = "current", lastSyncedAt: Date? = nil)` — both consumed by Task 4 (`SyncEngine`) and Task 6 (`TodayView`'s "Last synced" caption/staleness banner).

- [ ] **Step 1: Write the failing tests**

Add these two tests to `TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift`, inside the existing `ModelPersistenceTests` struct (after the existing `runningTimerRoundTrip` test, before the struct's closing `}`):

```swift
    @Test("TraxTask.syncedStatusId round-trips")
    func taskSyncedStatusIdRoundTrip() throws {
        let context = try makeContext()
        let task = TraxTask(
            id: "t3", projectId: "p1", name: "Synced task",
            priority: .normal, statusId: "s1", storyId: "st3", syncedStatusId: "s1"
        )
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TraxTask>(predicate: #Predicate { $0.id == "t3" }))
        #expect(fetched.first?.syncedStatusId == "s1")
    }

    @Test("SyncState round-trips")
    func syncStateRoundTrip() throws {
        let context = try makeContext()
        let syncedAt = Date(timeIntervalSince1970: 2000)
        let state = SyncState(lastSyncedAt: syncedAt)
        context.insert(state)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncState>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "current")
        #expect(fetched.first?.lastSyncedAt == syncedAt)
    }
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd TraxKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (use the `DEVELOPER_DIR` prefix if plain `swift test` fails with "plugin for module 'SwiftDataMacros' not found")
Expected: FAIL to compile — `TraxTask`'s `syncedStatusId` parameter and `SyncState` don't exist yet.

- [ ] **Step 3: Add `syncedStatusId` to `TraxTask`**

Replace the full contents of `TraxKit/Sources/TraxKit/Models/TraxTask.swift`:

```swift
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
```

- [ ] **Step 4: Create `SyncState`**

`TraxKit/Sources/TraxKit/Models/SyncState.swift`:

```swift
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
```

- [ ] **Step 5: Register `SyncState` in the schema**

In `TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift`, change:

```swift
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
```

to:

```swift
    public static var schema: Schema {
        Schema([
            Project.self,
            TaskStatus.self,
            TraxTask.self,
            Allocation.self,
            TimeEntry.self,
            RunningTimer.self,
            SyncState.self,
        ])
    }
```

- [ ] **Step 6: Run the tests, verify they pass**

Run: `cd TraxKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: All tests PASS (12 total), output pristine.

- [ ] **Step 7: Commit**

```bash
git add TraxKit/Sources/TraxKit/Models/TraxTask.swift TraxKit/Sources/TraxKit/Models/SyncState.swift TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift
git commit -m "$(cat <<'EOF'
Add TraxTask.syncedStatusId baseline field and SyncState model

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: KantataAPI additions — status-set workspace scoping, bounded allocation fetch, status-change push (TDD)

**Files:**
- Modify: `KantataAPI/Sources/KantataAPI/Client/Models/StatusSetDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/StoryStateChangeDTO.swift`
- Modify: `KantataAPI/Sources/KantataAPI/Client/KantataAPIClient.swift`
- Modify: `KantataAPI/Tests/KantataAPITests/DTODecodingTests.swift`
- Modify: `KantataAPI/Tests/KantataAPITests/KantataAPIClientTests.swift`

**Interfaces:**
- Produces: `StatusSetDTO.workspaceId` (new field), `StoryStateChangeDTO`/`StoryStateChangeCreateRequest`, `KantataAPIClient.fetchDailyScheduledHours(from:to:)` (now requires a date range), `KantataAPIClient.createStoryStateChange(_:)` — all consumed by Task 4 (`SyncEngine`).
- **Note:** `fetchDailyScheduledHours()` had no parameters before this task and nothing in the codebase calls it yet, so widening its signature here is not a breaking change to any existing call site.

- [ ] **Step 1: Write the failing tests**

Update the `statusSet` test in `KantataAPI/Tests/KantataAPITests/DTODecodingTests.swift` — replace:

```swift
    @Test("StatusSetDTO decodes with nested status ids")
    func statusSet() throws {
        let json = #"{"id": "set1", "name": "Default", "status_ids": ["s1", "s2"]}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StatusSetDTO.self, from: json)
        #expect(dto.id == "set1")
        #expect(dto.statusIds == ["s1", "s2"])
    }
```

with:

```swift
    @Test("StatusSetDTO decodes with nested status ids and a workspace id")
    func statusSet() throws {
        let json = #"{"id": "set1", "name": "Default", "workspace_id": "w1", "status_ids": ["s1", "s2"]}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StatusSetDTO.self, from: json)
        #expect(dto.id == "set1")
        #expect(dto.workspaceId == "w1")
        #expect(dto.statusIds == ["s1", "s2"])
    }
```

Add this new test to the same file, right before the closing `}` of the `DTODecodingTests` struct (after the `user` test):

```swift
    @Test("StoryStateChangeDTO decodes")
    func storyStateChange() throws {
        let json = #"{"id": "c1", "story_id": "st1", "status_id": "s2"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StoryStateChangeDTO.self, from: json)
        #expect(dto.storyId == "st1")
        #expect(dto.statusId == "s2")
    }
```

Add these two new tests to `KantataAPI/Tests/KantataAPITests/KantataAPIClientTests.swift`, right before the closing `}` of the `KantataAPIClientTests` struct:

```swift
    @Test("fetchDailyScheduledHours sends a from/to date range query")
    func fetchDailyScheduledHoursDateRange() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = "[]".data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        _ = try await client.fetchDailyScheduledHours(from: "2026-09-01", to: "2026-09-30")

        let query = transport.lastRequest?.url?.query ?? ""
        #expect(query.contains("from=2026-09-01"))
        #expect(query.contains("to=2026-09-30"))
    }

    @Test("createStoryStateChange posts the request body and decodes the response")
    func createStoryStateChange() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"id": "c1", "story_id": "st1", "status_id": "s2"}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        let result = try await client.createStoryStateChange(StoryStateChangeCreateRequest(storyId: "st1", statusId: "s2"))
        #expect(result.statusId == "s2")
        #expect(transport.lastRequest?.httpMethod == "POST")
    }
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd KantataAPI && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: FAIL to compile — `StatusSetDTO.workspaceId`, `StoryStateChangeDTO`, `fetchDailyScheduledHours(from:to:)`, and `createStoryStateChange` don't exist yet.

- [ ] **Step 3: Add `workspaceId` to `StatusSetDTO`**

Replace the full contents of `KantataAPI/Sources/KantataAPI/Client/Models/StatusSetDTO.swift`:

```swift
public struct StatusSetDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let workspaceId: String
    public let statusIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case workspaceId = "workspace_id"
        case statusIds = "status_ids"
    }
}
```

- [ ] **Step 4: Create `StoryStateChangeDTO`**

`KantataAPI/Sources/KantataAPI/Client/Models/StoryStateChangeDTO.swift`:

```swift
public struct StoryStateChangeDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    public let statusId: String

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case statusId = "status_id"
    }
}

public struct StoryStateChangeCreateRequest: Encodable, Sendable, Equatable {
    public let storyId: String
    public let statusId: String

    enum CodingKeys: String, CodingKey {
        case storyId = "story_id"
        case statusId = "status_id"
    }

    public init(storyId: String, statusId: String) {
        self.storyId = storyId
        self.statusId = statusId
    }
}
```

- [ ] **Step 5: Update `KantataAPIClient`**

Replace the full contents of `KantataAPI/Sources/KantataAPI/Client/KantataAPIClient.swift`:

```swift
import Foundation

public struct KantataAPIClient: Sendable {
    private let transport: any HTTPTransport
    private let baseURL: URL
    private let tokenProvider: @Sendable () -> String?

    public init(
        transport: any HTTPTransport,
        baseURL: URL = URL(string: "https://api.mavenlink.com/api/v1/")!,
        tokenProvider: @escaping @Sendable () -> String?
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    public func fetchTaskStatuses() async throws -> [TaskStatusDTO] {
        try await get("task_statuses")
    }

    public func fetchStatusSets() async throws -> [StatusSetDTO] {
        try await get("task_status_sets")
    }

    public func fetchAssignments() async throws -> [AssignmentDTO] {
        try await get("assignments")
    }

    public func fetchDailyScheduledHours(from: String, to: String) async throws -> [DailyScheduledHourDTO] {
        try await get("story_allocation_days", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ])
    }

    public func fetchStories() async throws -> [StoryDTO] {
        try await get("stories")
    }

    public func fetchCurrentUser() async throws -> UserDTO {
        try await get("me")
    }

    public func createTimeEntry(_ requestBody: TimeEntryCreateRequest) async throws -> TimeEntryDTO {
        try await post("time_entries", body: requestBody)
    }

    public func createStoryStateChange(_ requestBody: StoryStateChangeCreateRequest) async throws -> StoryStateChangeDTO {
        try await post("story_state_changes", body: requestBody)
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyAuth(&request)
        return try await send(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.send(request)
        try Self.validate(response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KantataAPIError.decodingFailed(error)
        }
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw KantataAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw KantataAPIError.httpError(http.statusCode)
        }
    }
}
```

- [ ] **Step 6: Run the tests, verify they pass**

Run: `cd KantataAPI && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: All tests PASS, output pristine.

- [ ] **Step 7: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/Client/Models/StatusSetDTO.swift KantataAPI/Sources/KantataAPI/Client/Models/StoryStateChangeDTO.swift KantataAPI/Sources/KantataAPI/Client/KantataAPIClient.swift KantataAPI/Tests/KantataAPITests/DTODecodingTests.swift KantataAPI/Tests/KantataAPITests/KantataAPIClientTests.swift
git commit -m "$(cat <<'EOF'
Add workspace-scoped status sets, bounded allocation fetch, and status-change push

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Conflict detection — `SyncConflict` and `detectConflicts` (TDD)

**Files:**
- Create: `TraxApp/Sources/TraxApp/SyncConflict.swift`
- Test: `TraxApp/Tests/TraxAppTests/SyncConflictTests.swift`

**Interfaces:**
- Produces: `struct ConflictCheckInput`, `struct SyncConflict: Equatable, Identifiable`, `enum ConflictResolution: Equatable { keepMine, useKantatas }`, `func detectConflicts(_ inputs: [ConflictCheckInput]) -> [SyncConflict]` — consumed by Task 4 (`SyncEngine`) and Task 7 (`ConflictResolutionView`).

- [ ] **Step 1: Write the failing tests**

`TraxApp/Tests/TraxAppTests/SyncConflictTests.swift`:

```swift
import Testing
@testable import TraxApp

@Suite("Conflict detection")
struct SyncConflictTests {
    private func input(
        localStatusId: String?,
        syncedStatusId: String?,
        remoteStatusId: String?
    ) -> ConflictCheckInput {
        ConflictCheckInput(
            taskId: "t1", taskName: "Design homepage",
            syncedStatusId: syncedStatusId,
            localStatusId: localStatusId, localStatusName: localStatusId ?? "No status",
            remoteStatusId: remoteStatusId, remoteStatusName: remoteStatusId ?? "No status"
        )
    }

    @Test("no conflict when only the local value changed")
    func localOnlyChange() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: "s1", remoteStatusId: "s1")])
        #expect(result.isEmpty)
    }

    @Test("no conflict when only the remote value changed")
    func remoteOnlyChange() {
        let result = detectConflicts([input(localStatusId: "s1", syncedStatusId: "s1", remoteStatusId: "s2")])
        #expect(result.isEmpty)
    }

    @Test("no conflict when both changed to the same value")
    func bothChangedSameValue() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: "s1", remoteStatusId: "s2")])
        #expect(result.isEmpty)
    }

    @Test("conflict when both changed to different values")
    func bothChangedDifferentValues() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: "s1", remoteStatusId: "s3")])
        #expect(result.count == 1)
        #expect(result.first?.localStatusId == "s2")
        #expect(result.first?.remoteStatusId == "s3")
    }

    @Test("no conflict when there is no baseline (never synced)")
    func neverSyncedNoBaseline() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: nil, remoteStatusId: "s3")])
        #expect(result.isEmpty)
    }

    @Test("no conflict when neither side changed")
    func noChange() {
        let result = detectConflicts([input(localStatusId: "s1", syncedStatusId: "s1", remoteStatusId: "s1")])
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `ConflictCheckInput`, `detectConflicts` don't exist yet.

- [ ] **Step 3: Implement `SyncConflict.swift`**

`TraxApp/Sources/TraxApp/SyncConflict.swift`:

```swift
struct ConflictCheckInput: Sendable {
    let taskId: String
    let taskName: String
    let syncedStatusId: String?
    let localStatusId: String?
    let localStatusName: String
    let remoteStatusId: String?
    let remoteStatusName: String
}

struct SyncConflict: Sendable, Equatable, Identifiable {
    var id: String { taskId }
    let taskId: String
    let taskName: String
    let localStatusId: String?
    let localStatusName: String
    let remoteStatusId: String?
    let remoteStatusName: String
}

enum ConflictResolution: Sendable, Equatable {
    case keepMine
    case useKantatas
}

func detectConflicts(_ inputs: [ConflictCheckInput]) -> [SyncConflict] {
    inputs.compactMap { input in
        guard let baseline = input.syncedStatusId else { return nil }
        let localChanged = input.localStatusId != baseline
        let remoteChanged = input.remoteStatusId != baseline
        guard localChanged, remoteChanged, input.localStatusId != input.remoteStatusId else { return nil }
        return SyncConflict(
            taskId: input.taskId,
            taskName: input.taskName,
            localStatusId: input.localStatusId,
            localStatusName: input.localStatusName,
            remoteStatusId: input.remoteStatusId,
            remoteStatusName: input.remoteStatusName
        )
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `SyncConflictTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/SyncConflict.swift TraxApp/Tests/TraxAppTests/SyncConflictTests.swift
git commit -m "$(cat <<'EOF'
Add pure conflict detection for task status sync

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `SyncEngine` — prepare and apply (TDD via stub transport)

**Files:**
- Create: `TraxApp/Sources/TraxApp/SyncEngine.swift`
- Test: `TraxApp/Tests/TraxAppTests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: `TraxTask`/`Allocation`/`TimeEntry`/`TaskStatus`/`SyncState` (`TraxKit`), `KantataAPIClient`/DTOs (`KantataAPI`), `ConflictCheckInput`/`SyncConflict`/`ConflictResolution`/`detectConflicts` (Task 3).
- Produces: `struct SyncPreparation`, `enum SyncError: Error, Equatable { partialFailure([String]), missingResolution(String) }`, `final class SyncEngine` with `prepareSync() async throws -> SyncPreparation` and `applySync(_:resolutions:) async throws` — consumed by Task 5 (`SyncController`).

- [ ] **Step 1: Write the failing tests**

`TraxApp/Tests/TraxAppTests/SyncEngineTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `SyncEngine`, `SyncPreparation`, `SyncError` don't exist yet.

- [ ] **Step 3: Implement `SyncEngine.swift`**

`TraxApp/Sources/TraxApp/SyncEngine.swift`:

```swift
import Foundation
import SwiftData
import TraxKit
import KantataAPI

struct SyncPreparation: Sendable {
    let remoteStatuses: [TaskStatusDTO]
    let remoteStatusSets: [StatusSetDTO]
    let remoteAssignments: [AssignmentDTO]
    let remoteStories: [StoryDTO]
    let remoteAllocations: [DailyScheduledHourDTO]
    let conflicts: [SyncConflict]
}

enum SyncError: Error, Equatable {
    case partialFailure([String])
    case missingResolution(String)
}

@MainActor
final class SyncEngine {
    private let modelContext: ModelContext
    private let apiClient: KantataAPIClient
    private let pastWindowDays: Int
    private let futureWindowDays: Int

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    init(
        modelContext: ModelContext,
        apiClient: KantataAPIClient,
        pastWindowDays: Int = 7,
        futureWindowDays: Int = 14
    ) {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.pastWindowDays = pastWindowDays
        self.futureWindowDays = futureWindowDays
    }

    func prepareSync() async throws -> SyncPreparation {
        let remoteStatuses = try await apiClient.fetchTaskStatuses()
        let remoteStatusSets = try await apiClient.fetchStatusSets()
        let remoteAssignments = try await apiClient.fetchAssignments()
        let remoteStories = try await apiClient.fetchStories()
        let (from, to) = dateWindow()
        let remoteAllocations = try await apiClient.fetchDailyScheduledHours(from: from, to: to)

        let localTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        let localStatuses = try modelContext.fetch(FetchDescriptor<TaskStatus>())
        let localStatusNamesById = Dictionary(uniqueKeysWithValues: localStatuses.map { ($0.id, $0.name) })
        let remoteStatusNamesById = Dictionary(uniqueKeysWithValues: remoteStatuses.map { ($0.id, $0.name) })
        let remoteStoriesById = Dictionary(uniqueKeysWithValues: remoteStories.map { ($0.id, $0) })

        let inputs: [ConflictCheckInput] = localTasks.compactMap { task in
            guard let remoteStory = remoteStoriesById[task.id] else { return nil }
            return ConflictCheckInput(
                taskId: task.id,
                taskName: task.name,
                syncedStatusId: task.syncedStatusId,
                localStatusId: task.statusId,
                localStatusName: Self.statusName(for: task.statusId, in: localStatusNamesById),
                remoteStatusId: remoteStory.statusId,
                remoteStatusName: Self.statusName(for: remoteStory.statusId, in: remoteStatusNamesById)
            )
        }

        return SyncPreparation(
            remoteStatuses: remoteStatuses,
            remoteStatusSets: remoteStatusSets,
            remoteAssignments: remoteAssignments,
            remoteStories: remoteStories,
            remoteAllocations: remoteAllocations,
            conflicts: detectConflicts(inputs)
        )
    }

    func applySync(_ preparation: SyncPreparation, resolutions: [String: ConflictResolution]) async throws {
        var useKantatasTaskIds: Set<String> = []
        for conflict in preparation.conflicts {
            guard let resolution = resolutions[conflict.taskId] else {
                throw SyncError.missingResolution(conflict.taskId)
            }
            if resolution == .useKantatas {
                useKantatasTaskIds.insert(conflict.taskId)
                if let task = try taskById(conflict.taskId) {
                    task.statusId = conflict.remoteStatusId
                }
            }
        }

        var failures: [String] = []

        let unsyncedEntries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.synced == false })
        )
        for entry in unsyncedEntries {
            do {
                let dateString = Self.isoDateFormatter.string(from: entry.date)
                let hours = Double(entry.minutes) / 60
                _ = try await apiClient.createTimeEntry(
                    TimeEntryCreateRequest(storyId: entry.taskId, date: dateString, hours: hours)
                )
                entry.synced = true
            } catch {
                failures.append("time entry for \(entry.taskId)")
            }
        }

        let localTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        for task in localTasks {
            guard !useKantatasTaskIds.contains(task.id) else { continue }
            guard task.statusId != task.syncedStatusId, let newStatusId = task.statusId else { continue }
            do {
                _ = try await apiClient.createStoryStateChange(
                    StoryStateChangeCreateRequest(storyId: task.storyId, statusId: newStatusId)
                )
            } catch {
                failures.append("status for \(task.name)")
            }
        }

        let existingStatuses = try modelContext.fetch(FetchDescriptor<TaskStatus>())
        for status in existingStatuses {
            modelContext.delete(status)
        }
        let statusNamesById = Dictionary(uniqueKeysWithValues: preparation.remoteStatuses.map { ($0.id, $0.name) })
        for statusSet in preparation.remoteStatusSets {
            for statusId in statusSet.statusIds {
                guard let name = statusNamesById[statusId] else { continue }
                modelContext.insert(TaskStatus(id: statusId, projectId: statusSet.workspaceId, name: name))
            }
        }

        let storiesById = Dictionary(uniqueKeysWithValues: preparation.remoteStories.map { ($0.id, $0) })
        let refreshedLocalTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        let localTasksById = Dictionary(uniqueKeysWithValues: refreshedLocalTasks.map { ($0.id, $0) })
        for assignment in preparation.remoteAssignments {
            guard let story = storiesById[assignment.storyId] else { continue }
            if let existing = localTasksById[story.id] {
                existing.name = story.title
                existing.priority = Self.priority(from: story.priority)
                existing.dueDate = story.dueDate.flatMap { Self.isoDateFormatter.date(from: $0) }
            } else {
                modelContext.insert(TraxTask(
                    id: story.id,
                    projectId: story.workspaceId,
                    name: story.title,
                    priority: Self.priority(from: story.priority),
                    dueDate: story.dueDate.flatMap { Self.isoDateFormatter.date(from: $0) },
                    statusId: story.statusId,
                    storyId: story.id,
                    syncedStatusId: story.statusId
                ))
            }
        }

        let (from, to) = dateWindow()
        if let fromDate = Self.isoDateFormatter.date(from: from), let toDate = Self.isoDateFormatter.date(from: to) {
            let existingAllocations = try modelContext.fetch(
                FetchDescriptor<Allocation>(predicate: #Predicate { $0.date >= fromDate && $0.date <= toDate })
            )
            for allocation in existingAllocations {
                modelContext.delete(allocation)
            }
        }
        for dto in preparation.remoteAllocations {
            guard let date = Self.isoDateFormatter.date(from: dto.date) else { continue }
            modelContext.insert(Allocation(
                id: dto.id, taskId: dto.storyId, date: date,
                scheduledMinutes: Int((dto.hours * 60).rounded())
            ))
        }

        let finalTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        for task in finalTasks {
            task.syncedStatusId = task.statusId
        }

        let syncStates = try modelContext.fetch(FetchDescriptor<SyncState>())
        let syncState = syncStates.first ?? SyncState()
        if syncStates.isEmpty {
            modelContext.insert(syncState)
        }
        syncState.lastSyncedAt = .now

        try modelContext.save()

        if !failures.isEmpty {
            throw SyncError.partialFailure(failures)
        }
    }

    private func taskById(_ id: String) throws -> TraxTask? {
        try modelContext.fetch(FetchDescriptor<TraxTask>(predicate: #Predicate { $0.id == id })).first
    }

    private func dateWindow() -> (from: String, to: String) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let from = calendar.date(byAdding: .day, value: -pastWindowDays, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: futureWindowDays, to: today) ?? today
        return (Self.isoDateFormatter.string(from: from), Self.isoDateFormatter.string(from: to))
    }

    private static func statusName(for id: String?, in namesById: [String: String]) -> String {
        guard let id else { return "No status" }
        return namesById[id] ?? "Unknown status"
    }

    private static func priority(from raw: String?) -> Priority {
        switch raw?.lowercased() {
        case "critical": return .critical
        case "high": return .high
        case "normal": return .normal
        case "low": return .low
        default: return .none
        }
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `SyncEngineTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/SyncEngine.swift TraxApp/Tests/TraxAppTests/SyncEngineTests.swift
git commit -m "$(cat <<'EOF'
Add SyncEngine: two-phase prepare/apply push-pull sync

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `SyncController` (TDD)

**Files:**
- Create: `TraxApp/Sources/TraxApp/SyncController.swift`
- Test: `TraxApp/Tests/TraxAppTests/SyncControllerTests.swift`

**Interfaces:**
- Consumes: `SyncEngine`, `SyncPreparation`, `SyncError`, `SyncConflict`, `ConflictResolution` (Task 4/3), `RoutingStubTransport` (Task 4's test file, same test target).
- Produces: `enum SyncPhase: Equatable { idle, syncing, conflicts([SyncConflict]), failed(String) }`, `final class SyncController` with `phase`, `isSyncing`, `startSync()`, `resolveConflicts(_:)`, `cancelConflicts()`, `dismissFailure()` — consumed by Task 6/7 (`TodayView`, `ConflictResolutionView`).

- [ ] **Step 1: Write the failing tests**

`TraxApp/Tests/TraxAppTests/SyncControllerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `SyncController`, `SyncPhase` don't exist yet.

- [ ] **Step 3: Implement `SyncController.swift`**

`TraxApp/Sources/TraxApp/SyncController.swift`:

```swift
import Foundation
import KantataAPI

enum SyncPhase: Equatable {
    case idle
    case syncing
    case conflicts([SyncConflict])
    case failed(String)
}

@MainActor
@Observable
final class SyncController {
    private(set) var phase: SyncPhase = .idle
    private let engine: SyncEngine
    private var pendingPreparation: SyncPreparation?

    init(engine: SyncEngine) {
        self.engine = engine
    }

    var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
    }

    func startSync() async {
        phase = .syncing
        do {
            let preparation = try await engine.prepareSync()
            if preparation.conflicts.isEmpty {
                try await engine.applySync(preparation, resolutions: [:])
                phase = .idle
            } else {
                pendingPreparation = preparation
                phase = .conflicts(preparation.conflicts)
            }
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func resolveConflicts(_ resolutions: [String: ConflictResolution]) async {
        guard let preparation = pendingPreparation else { return }
        phase = .syncing
        do {
            try await engine.applySync(preparation, resolutions: resolutions)
            phase = .idle
            pendingPreparation = nil
        } catch {
            phase = .failed(Self.message(for: error))
            pendingPreparation = nil
        }
    }

    func cancelConflicts() {
        pendingPreparation = nil
        phase = .idle
    }

    func dismissFailure() {
        phase = .idle
    }

    private static func message(for error: Error) -> String {
        if case KantataAPIError.unauthorized = error {
            return "Your Kantata connection needs to be reconnected."
        }
        if case SyncError.partialFailure(let items) = error {
            return "Couldn't sync: \(items.joined(separator: ", "))."
        }
        return "Couldn't reach Kantata. Check your connection and try again."
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `SyncControllerTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/SyncController.swift TraxApp/Tests/TraxAppTests/SyncControllerTests.swift
git commit -m "$(cat <<'EOF'
Add SyncController state machine wrapping SyncEngine

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Toolbar wiring — sync button, last-synced caption, staleness banner

**Files:**
- Modify: `TraxApp/Sources/TraxApp/AuthGateView.swift`
- Modify: `TraxApp/Sources/TraxApp/TodayView.swift`

**Interfaces:**
- Consumes: `SyncController`, `SyncEngine` (Tasks 4/5), `KantataAPIClient`/`URLSessionHTTPTransport`/`TokenStore` (`KantataAPI`), `SyncState` (`TraxKit`).
- Produces: `TodayView(apiClient: KantataAPIClient)` (new initializer parameter) — the `syncController` this task establishes is consumed by Task 7 (the overlay/modal/toast layer, which reads its `phase`).

- [ ] **Step 1: Wire a real `KantataAPIClient` into `AuthGateView`**

Replace the full contents of `TraxApp/Sources/TraxApp/AuthGateView.swift`:

```swift
import SwiftUI
import KantataAPI

struct AuthGateView: View {
    @State private var controller: AuthFlowController
    private let apiClient: KantataAPIClient

    init(oauthClient: any OAuthClient, tokenStore: any TokenStore) {
        _controller = State(initialValue: AuthFlowController(oauthClient: oauthClient, tokenStore: tokenStore))
        apiClient = KantataAPIClient(
            transport: URLSessionHTTPTransport(),
            tokenProvider: { try? tokenStore.load()?.accessToken }
        )
    }

    var body: some View {
        if controller.state == .signedIn {
            TodayView(apiClient: apiClient)
        } else {
            FirstLaunchView(controller: controller)
        }
    }
}
```

- [ ] **Step 2: Wire the toolbar and staleness banner into `TodayView`**

Replace the full contents of `TraxApp/Sources/TraxApp/TodayView.swift`:

```swift
import SwiftUI
import SwiftData
import TraxKit
import KantataAPI

struct TodayView: View {
    let apiClient: KantataAPIClient

    @Environment(\.modelContext) private var modelContext
    @Query private var syncStates: [SyncState]
    @State private var syncController: SyncController?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var now: Date = .now
    private let clockTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var lastSyncedAt: Date? {
        syncStates.first?.lastSyncedAt
    }

    private var lastSyncedLabel: String {
        guard let lastSyncedAt else { return "Never synced" }
        return "Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))"
    }

    private var isStale: Bool {
        guard let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) > 10 * 3600
    }

    private var staleBannerText: String {
        guard let lastSyncedAt else { return "You haven't synced yet. Your schedule may be out of date." }
        let hours = Int(now.timeIntervalSince(lastSyncedAt) / 3600)
        return "\(hours) hours since last sync. Your schedule may be out of date."
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if isStale {
                staleBanner
            }
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
            Divider()
            AddTimeRow(date: selectedDate)
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if syncController == nil {
                syncController = SyncController(engine: SyncEngine(modelContext: modelContext, apiClient: apiClient))
            }
        }
        .onReceive(clockTicker) { now = $0 }
    }

    private var toolbar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Text(dateLabel)
                        .font(.headline)
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                Spacer()
                Button {
                    Task { await syncController?.startSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(syncController == nil)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Text(lastSyncedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private var staleBanner: some View {
        HStack {
            Text(staleBannerText)
                .font(.caption)
            Spacer()
            Button("Sync now") {
                Task { await syncController?.startSync() }
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.2))
    }
}

#Preview {
    TodayView(apiClient: KantataAPIClient(transport: URLSessionHTTPTransport(), tokenProvider: { nil }))
}
```

- [ ] **Step 3: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add TraxApp/Sources/TraxApp/AuthGateView.swift TraxApp/Sources/TraxApp/TodayView.swift
git commit -m "$(cat <<'EOF'
Wire sync button, last-synced caption, and staleness banner

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Sync overlays — dimming, conflict modal, failure toast

**Files:**
- Create: `TraxApp/Sources/TraxApp/ConflictResolutionView.swift`
- Modify: `TraxApp/Sources/TraxApp/TodayView.swift`

**Interfaces:**
- Consumes: `SyncController`, `SyncPhase` (Task 5), `SyncConflict`, `ConflictResolution` (Task 3).
- Produces: `ConflictResolutionView`, and `TodayView`'s completed sync-state visuals (dimming overlay, blocking conflict modal, non-blocking failure toast).

- [ ] **Step 1: Create `ConflictResolutionView`**

`TraxApp/Sources/TraxApp/ConflictResolutionView.swift`:

```swift
import SwiftUI

struct ConflictResolutionView: View {
    let conflicts: [SyncConflict]
    let onApply: ([String: ConflictResolution]) -> Void
    let onCancel: () -> Void

    @State private var resolutions: [String: ConflictResolution] = [:]

    private var allResolved: Bool {
        conflicts.allSatisfy { resolutions[$0.taskId] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resolve conflicts")
                .font(.title2)
                .bold()
            Text("These fields changed both locally and on Kantata since your last sync.")
                .foregroundStyle(.secondary)

            ForEach(conflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.taskName)
                        .font(.headline)
                    HStack {
                        Button("Keep mine (\(conflict.localStatusName))") {
                            resolutions[conflict.taskId] = .keepMine
                        }
                        .buttonStyle(resolutions[conflict.taskId] == .keepMine ? .borderedProminent : .bordered)

                        Button("Use Kantata's (\(conflict.remoteStatusName))") {
                            resolutions[conflict.taskId] = .useKantatas
                        }
                        .buttonStyle(resolutions[conflict.taskId] == .useKantatas ? .borderedProminent : .bordered)
                    }
                    if resolutions[conflict.taskId] == nil {
                        Text("Choose one")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button("Cancel sync", role: .destructive) {
                    onCancel()
                }
                Spacer()
                Button("Apply and continue sync") {
                    onApply(resolutions)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allResolved)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 2: Add the overlay layers to `TodayView`**

In `TraxApp/Sources/TraxApp/TodayView.swift`, replace:

```swift
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if isStale {
                staleBanner
            }
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
            Divider()
            AddTimeRow(date: selectedDate)
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if syncController == nil {
                syncController = SyncController(engine: SyncEngine(modelContext: modelContext, apiClient: apiClient))
            }
        }
        .onReceive(clockTicker) { now = $0 }
    }
```

with:

```swift
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                if isStale {
                    staleBanner
                }
                Divider()
                RunningTimerBanner()
                TaskListView(selectedDate: selectedDate)
                Divider()
                AddTimeRow(date: selectedDate)
            }
            .disabled(syncController?.isSyncing ?? false)

            if syncController?.isSyncing == true {
                syncingOverlay
            }

            if let syncController, case .conflicts(let conflicts) = syncController.phase {
                conflictOverlay(conflicts: conflicts, controller: syncController)
            }

            if let syncController, case .failed(let message) = syncController.phase {
                failureToast(message: message, controller: syncController)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if syncController == nil {
                syncController = SyncController(engine: SyncEngine(modelContext: modelContext, apiClient: apiClient))
            }
        }
        .onReceive(clockTicker) { now = $0 }
    }

    private var syncingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Syncing with Kantata…")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func conflictOverlay(conflicts: [SyncConflict], controller: SyncController) -> some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ConflictResolutionView(
                conflicts: conflicts,
                onApply: { resolutions in
                    Task { await controller.resolveConflicts(resolutions) }
                },
                onCancel: {
                    controller.cancelConflicts()
                }
            )
        }
    }

    private func failureToast(message: String, controller: SyncController) -> some View {
        VStack {
            Spacer()
            HStack {
                Text(message)
                    .foregroundStyle(.white)
                Spacer()
                Button("Retry") {
                    Task { await controller.startSync() }
                }
                .foregroundStyle(.white)
                Button("Dismiss") {
                    controller.dismissFailure()
                }
                .foregroundStyle(.white)
            }
            .padding()
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
        }
    }
```

- [ ] **Step 3: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add TraxApp/Sources/TraxApp/ConflictResolutionView.swift TraxApp/Sources/TraxApp/TodayView.swift
git commit -m "$(cat <<'EOF'
Add sync-in-progress dimming, conflict modal, and failure toast

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** Manual push (time entries, status changes) and pull (assignments, allocations, statuses) — Task 4. Per-field (status-only) conflict resolution with no default selection, "Choose one" hint, disabled "Apply and continue" until all resolved, "Cancel sync" aborting the whole attempt — Tasks 3, 4, 7. Sync-in-progress dimming/disabling and "Syncing with Kantata…" — Task 7. Staleness banner (>10h) with its own "Sync now" — Task 6. Failure toast with reason, Retry, dismiss — Task 7. `SyncState`/baseline model support — Task 1. `KantataAPI` push/pull surface needed by the engine — Task 2. Explicitly out of scope per the design doc: conflict handling for scheduled/logged time, automatic sync, token-refresh/re-auth flows, and unassigned-task archival — none of that is touched by any task.
- **Placeholder scan:** none found — every step has concrete, complete code.
- **Type consistency:** `TraxTask.syncedStatusId`/`SyncState` (Task 1) flow into `SyncEngine` (Task 4) with matching field names. `StatusSetDTO.workspaceId`, `fetchDailyScheduledHours(from:to:)`, `createStoryStateChange` (Task 2) are called with matching signatures in `SyncEngine` (Task 4). `ConflictCheckInput`/`SyncConflict`/`ConflictResolution`/`detectConflicts` (Task 3) are consumed identically by `SyncEngine` (Task 4) and `ConflictResolutionView` (Task 7). `SyncPreparation`/`SyncError` (Task 4) are the exact types `SyncController` (Task 5) catches and switches on. `SyncController`'s `phase`/`isSyncing`/`startSync()`/`resolveConflicts(_:)`/`cancelConflicts()`/`dismissFailure()` (Task 5) are used with matching names throughout `TodayView` (Tasks 6, 7) and `ConflictResolutionView` (Task 7). `RoutingStubTransport` is defined once in Task 4's test file and reused by name in Task 5's test file — both live in the same `TraxAppTests` target, so no import/visibility issue.
