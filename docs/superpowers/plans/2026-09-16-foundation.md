# Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `TraxKit` Swift package with domain models, local persistence, and the duration parser that the rest of Trax (UI, auth/API, sync) builds on.

**Architecture:** A standalone Swift package (`TraxKit/`) at the repo root, buildable and testable via the `swift` CLI alone — no Xcode project yet, since there's no UI to host until sub-project #2. It exposes SwiftData `@Model` domain types, a `PersistenceController` for creating a `ModelContainer`, and a pure `parseDuration` function. The app target (added in sub-project #2) will add this package as a local dependency.

**Tech Stack:** Swift 6 toolchain, macOS 14+ deployment target, SwiftData for persistence, Swift Testing (`import Testing`, `@Test`/`#expect`) for tests.

**Spec:** `docs/superpowers/specs/2026-09-16-foundation-design.md` (and top-level `SPEC.md` § Duration parser, § Mixed scheduled / unscheduled tasks, § Status for the behavior these models encode)

## Global Constraints

- macOS 14+ deployment target (`platforms: [.macOS(.v14)]` in `Package.swift`) — required for SwiftData.
- Swift Testing, not XCTest, for all tests in this plan.
- No sync/conflict-tracking fields beyond `TimeEntry.synced` — that's sub-project #4's design to own.
- The SwiftData model that represents a Kantata task/story is named `TraxTask`, not `Task` — Swift's concurrency `Task` type lives in the same implicit namespace and a model literally named `Task` creates ambiguous-lookup errors anywhere `Task { }` (structured concurrency) is used later in the app. This is a naming correction to the design doc, not a scope change — same fields, same behavior.

---

### Task 1: Package scaffold + `Priority` enum

**Files:**
- Create: `TraxKit/Package.swift`
- Create: `TraxKit/Sources/TraxKit/Models/Priority.swift`

**Interfaces:**
- Produces: `public enum Priority: String, Codable, CaseIterable, Sendable { case critical, high, normal, low, none }` — consumed by `TraxTask` in Task 3.

- [ ] **Step 1: Create the package manifest**

`TraxKit/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraxKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TraxKit", targets: ["TraxKit"]),
    ],
    targets: [
        .target(name: "TraxKit"),
        .testTarget(
            name: "TraxKitTests",
            dependencies: ["TraxKit"]
        ),
    ]
)
```

- [ ] **Step 2: Add the `Priority` enum**

`TraxKit/Sources/TraxKit/Models/Priority.swift`:
```swift
public enum Priority: String, Codable, CaseIterable, Sendable {
    case critical
    case high
    case normal
    case low
    case none
}
```

- [ ] **Step 3: Verify the package builds**

Run: `cd TraxKit && swift build`
Expected: `Build complete!` with no errors (a "no tests" note from the empty test target is fine).

- [ ] **Step 4: Commit**

```bash
git add TraxKit/Package.swift TraxKit/Sources/TraxKit/Models/Priority.swift
git commit -m "$(cat <<'EOF'
Scaffold TraxKit package with Priority enum

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Duration parser (TDD)

**Files:**
- Create: `TraxKit/Sources/TraxKit/DurationParser.swift`
- Test: `TraxKit/Tests/TraxKitTests/DurationParserTests.swift`

**Interfaces:**
- Consumes: nothing (pure function, no dependency on Task 1's types).
- Produces: `public enum DurationParseError: Error, Equatable, Sendable { case empty, unparseable, negative, minutesOutOfRange, exceedsMax }` and `public func parseDuration(_ input: String) -> Result<Int, DurationParseError>` — consumed by sub-project #2's time-entry UI.

- [ ] **Step 1: Write the failing tests**

`TraxKit/Tests/TraxKitTests/DurationParserTests.swift`:
```swift
import Testing
@testable import TraxKit

@Suite("Duration parser")
struct DurationParserTests {

    @Test("accepted forms", arguments: [
        ("2h45m", 165),
        ("2h 45m", 165),
        ("2h", 120),
        ("45m", 45),
        ("2:45", 165),
        ("1", 60),
        ("0.75", 45),
        ("1.5", 90),
        ("2H45M", 165),
    ])
    func acceptedForms(input: String, expectedMinutes: Int) {
        #expect(parseDuration(input) == .success(expectedMinutes))
    }

    @Test("rejected forms", arguments: [
        ("", DurationParseError.empty),
        ("abc", DurationParseError.unparseable),
        ("-5", DurationParseError.negative),
        ("1h90m", DurationParseError.minutesOutOfRange),
        ("2:75", DurationParseError.minutesOutOfRange),
        ("25h", DurationParseError.exceedsMax),
        ("1441m", DurationParseError.exceedsMax),
    ])
    func rejectedForms(input: String, expectedError: DurationParseError) {
        #expect(parseDuration(input) == .failure(expectedError))
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd TraxKit && swift test`
Expected: FAIL to compile — `parseDuration` and `DurationParseError` don't exist yet.

- [ ] **Step 3: Implement the parser**

`TraxKit/Sources/TraxKit/DurationParser.swift`:
```swift
import Foundation

public enum DurationParseError: Error, Equatable, Sendable {
    case empty
    case unparseable
    case negative
    case minutesOutOfRange
    case exceedsMax
}

private let maxMinutes = 1440

public func parseDuration(_ input: String) -> Result<Int, DurationParseError> {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .failure(.empty) }

    let lower = trimmed.lowercased()

    if lower.contains("h") || lower.contains("m") {
        return parseUnitForm(lower)
    }
    if lower.contains(":") {
        return parseColonForm(lower)
    }
    return parseBareNumber(lower)
}

private func parseUnitForm(_ input: String) -> Result<Int, DurationParseError> {
    if let match = input.firstMatch(of: /^(\d+(?:\.\d+)?)h\s*(\d+)m$/) {
        guard let hours = Double(match.1) else { return .failure(.unparseable) }
        guard let minutes = Int(match.2) else { return .failure(.unparseable) }
        if minutes >= 60 { return .failure(.minutesOutOfRange) }
        return finalize(Int((hours * 60).rounded()) + minutes)
    }
    if let match = input.firstMatch(of: /^(\d+(?:\.\d+)?)h$/) {
        guard let hours = Double(match.1) else { return .failure(.unparseable) }
        return finalize(Int((hours * 60).rounded()))
    }
    if let match = input.firstMatch(of: /^(\d+)m$/) {
        guard let minutes = Int(match.1) else { return .failure(.unparseable) }
        return finalize(minutes)
    }
    return .failure(.unparseable)
}

private func parseColonForm(_ input: String) -> Result<Int, DurationParseError> {
    guard let match = input.firstMatch(of: /^(\d+):(\d{1,2})$/) else {
        return .failure(.unparseable)
    }
    guard let hours = Int(match.1), let minutes = Int(match.2) else {
        return .failure(.unparseable)
    }
    if minutes >= 60 { return .failure(.minutesOutOfRange) }
    return finalize(hours * 60 + minutes)
}

private func parseBareNumber(_ input: String) -> Result<Int, DurationParseError> {
    guard let value = Double(input) else { return .failure(.unparseable) }
    if value < 0 { return .failure(.negative) }
    return finalize(Int((value * 60).rounded()))
}

private func finalize(_ totalMinutes: Int) -> Result<Int, DurationParseError> {
    if totalMinutes < 0 { return .failure(.negative) }
    if totalMinutes > maxMinutes { return .failure(.exceedsMax) }
    return .success(totalMinutes)
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `cd TraxKit && swift test`
Expected: All tests in `DurationParserTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxKit/Sources/TraxKit/DurationParser.swift TraxKit/Tests/TraxKitTests/DurationParserTests.swift
git commit -m "$(cat <<'EOF'
Add duration parser with full grammar coverage

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Domain models + persistence layer (TDD)

**Files:**
- Create: `TraxKit/Sources/TraxKit/Models/Project.swift`
- Create: `TraxKit/Sources/TraxKit/Models/TaskStatus.swift`
- Create: `TraxKit/Sources/TraxKit/Models/TraxTask.swift`
- Create: `TraxKit/Sources/TraxKit/Models/Allocation.swift`
- Create: `TraxKit/Sources/TraxKit/Models/TimeEntry.swift`
- Create: `TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift`
- Test: `TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift`

**Interfaces:**
- Consumes: `Priority` from Task 1.
- Produces:
  - `Project(id: String, name: String, colorHex: String, workspaceURL: URL)`
  - `TaskStatus(id: String, name: String)`
  - `TraxTask(id: String, projectId: String, name: String, priority: Priority, dueDate: Date? = nil, statusId: String? = nil, storyId: String)`
  - `Allocation(id: String, taskId: String, date: Date, scheduledMinutes: Int)`
  - `TimeEntry(id: String = UUID().uuidString, taskId: String, date: Date, minutes: Int, synced: Bool = false, createdAt: Date = .now)`
  - `PersistenceController.makeContainer(inMemory: Bool = false) throws -> ModelContainer`
  - All consumed by sub-project #2 (UI) and #4 (sync).

- [ ] **Step 1: Write the failing tests**

`TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift`:
```swift
import Foundation
import SwiftData
import Testing
@testable import TraxKit

@Suite("Model persistence round-trips")
@MainActor
struct ModelPersistenceTests {

    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Project round-trips")
    func projectRoundTrip() throws {
        let context = try makeContext()
        let project = Project(
            id: "p1",
            name: "Acme Redesign",
            colorHex: "#FF0000",
            workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/p1")!
        )
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "p1")
        #expect(fetched.first?.name == "Acme Redesign")
    }

    @Test("TraxTask round-trips")
    func taskRoundTrip() throws {
        let context = try makeContext()
        let task = TraxTask(
            id: "t1", projectId: "p1", name: "Design homepage",
            priority: .high, dueDate: nil, statusId: nil, storyId: "s1"
        )
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TraxTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.priority == .high)
        #expect(fetched.first?.statusId == nil)
    }

    @Test("Allocation round-trips")
    func allocationRoundTrip() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)
        let allocation = Allocation(id: "a1", taskId: "t1", date: date, scheduledMinutes: 90)
        context.insert(allocation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Allocation>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.scheduledMinutes == 90)
    }

    @Test("TimeEntry round-trips")
    func timeEntryRoundTrip() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)
        let entry = TimeEntry(taskId: "t1", date: date, minutes: 45)
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.synced == false)
        #expect(fetched.first?.minutes == 45)
    }

    @Test("Logging time against an unscheduled task creates no Allocation")
    func unscheduledTaskTimeEntryCreatesNoAllocation() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)
        let task = TraxTask(id: "t2", projectId: "p1", name: "Unscheduled task", priority: .none, storyId: "s2")
        context.insert(task)

        let entry = TimeEntry(taskId: "t2", date: date, minutes: 30)
        context.insert(entry)
        try context.save()

        let allocations = try context.fetch(
            FetchDescriptor<Allocation>(predicate: #Predicate { $0.taskId == "t2" })
        )
        #expect(allocations.isEmpty)

        let entries = try context.fetch(
            FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.taskId == "t2" })
        )
        #expect(entries.count == 1)
        #expect(entries.first?.minutes == 30)
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd TraxKit && swift test`
Expected: FAIL to compile — `Project`, `TraxTask`, `Allocation`, `TimeEntry`, `PersistenceController` don't exist yet.

- [ ] **Step 3: Create the model types**

`TraxKit/Sources/TraxKit/Models/Project.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class Project {
    @Attribute(.unique) public var id: String
    public var name: String
    public var colorHex: String
    public var workspaceURL: URL

    public init(id: String, name: String, colorHex: String, workspaceURL: URL) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.workspaceURL = workspaceURL
    }
}
```

`TraxKit/Sources/TraxKit/Models/TaskStatus.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class TaskStatus {
    @Attribute(.unique) public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
```

`TraxKit/Sources/TraxKit/Models/TraxTask.swift`:
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

    public init(
        id: String,
        projectId: String,
        name: String,
        priority: Priority,
        dueDate: Date? = nil,
        statusId: String? = nil,
        storyId: String
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.priority = priority
        self.dueDate = dueDate
        self.statusId = statusId
        self.storyId = storyId
    }
}
```

`TraxKit/Sources/TraxKit/Models/Allocation.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class Allocation {
    @Attribute(.unique) public var id: String
    public var taskId: String
    public var date: Date
    public var scheduledMinutes: Int

    public init(id: String, taskId: String, date: Date, scheduledMinutes: Int) {
        self.id = id
        self.taskId = taskId
        self.date = date
        self.scheduledMinutes = scheduledMinutes
    }
}
```

`TraxKit/Sources/TraxKit/Models/TimeEntry.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class TimeEntry {
    @Attribute(.unique) public var id: String
    public var taskId: String
    public var date: Date
    public var minutes: Int
    public var synced: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        date: Date,
        minutes: Int,
        synced: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.taskId = taskId
        self.date = date
        self.minutes = minutes
        self.synced = synced
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Create the persistence controller**

`TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift`:
```swift
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
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `cd TraxKit && swift test`
Expected: All tests PASS, including `unscheduledTaskTimeEntryCreatesNoAllocation`.

- [ ] **Step 6: Commit**

```bash
git add TraxKit/Sources/TraxKit/Models TraxKit/Sources/TraxKit/Persistence TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift
git commit -m "$(cat <<'EOF'
Add domain models and SwiftData persistence layer

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** Duration parser grammar (all 5 accepted forms + rejection rules) — Task 2. Domain models for Project/Task/Allocation/TimeEntry/TaskStatus and the "no allocation created" behavior from § Mixed scheduled / unscheduled tasks — Task 3. Sync/conflict fields, UI, and auth are explicitly out of scope per the design doc and deferred to sub-projects #2–#4.
- **Placeholder scan:** none found — every step has concrete code.
- **Type consistency:** `Priority` (Task 1) → used verbatim in `TraxTask` (Task 3). `DurationParseError` / `parseDuration` (Task 2) are self-contained, no cross-task dependency. `PersistenceController.makeContainer` (Task 3) matches its use in the test file written in the same task.
