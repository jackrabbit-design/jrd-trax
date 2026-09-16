# Today View UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable SwiftUI app (`TraxApp`) implementing the full Today view — toolbar, running timer, grouped/sorted task list, quick-add and bottom-row time entry, status editing, and deep links — against seeded sample data, with no networking yet.

**Architecture:** A new root-level Swift package (`Package.swift` at the repo root) with an executable target `TraxApp` depending on the already-merged `TraxKit` library package via a local path dependency. No `.xcodeproj`. Pure/testable logic (sort order, duration-field validation, date/duration formatting, elapsed-time math) lives in small standalone files with their own Swift Testing coverage; SwiftUI views are thin and read via `@Query`/`@Environment(\.modelContext)`.

**Tech Stack:** Swift 6 toolchain, macOS 14+ deployment target, SwiftUI, SwiftData (`@Query`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-16-today-view-ui-design.md` (and top-level `SPEC.md` §§ Screen: today view, Time entry, Status, Project/task links for the behavior this implements)

## Global Constraints

- macOS 14+ deployment target, matching `TraxKit`.
- Swift Testing, not XCTest, for all tests.
- `TraxApp` is a plain SPM executable target (no `.xcodeproj`) — see the design doc's Platform section for why.
- The running timer is tied to "now," not to the day being viewed: starting/stopping always uses `Calendar.current.startOfDay(for: .now)`. Quick-add (per-row) and the bottom add-time row log against `selectedDate` (the day currently on screen), which is itself always `Calendar.current.startOfDay(for:)`-normalized so it compares equal to normalized `Allocation`/`TimeEntry` dates.
- Starting a timer on a task always removes any existing `RunningTimer` row first — only one timer runs at a time.
- Stopping the timer creates a local `TimeEntry` (`synced: false` is the default) only if elapsed rounds to ≥ 1 minute; it never pushes to Kantata (no sync exists yet).
- **Known limitation, not a defect to fix in this plan:** `RunningTimer` is modeled for on-disk persistence (per the brainstorming decision that a timer survives app relaunch), but this sub-project seeds an **in-memory** `ModelContainer` for sample data (per the earlier brainstorming decision on dev data source). Relaunch-persistence isn't observable until a later sub-project switches to on-disk storage — the model and logic are written correctly for it regardless.
- The sync button exists in the toolbar (per spec layout) but is disabled/inert — wired up in a future sub-project.
- No first-launch auth screen — `TraxApp`'s `WindowGroup` shows `TodayView` directly.
- Task/project deep links use the URL pattern from `SPEC.md` (`https://app.mavenlink.com/workspaces/{project_id}` and `.../workspaces/{project_id}/stories/{story_id}`), flagged there as unverified against Kantata's real routes — out of scope to fix here.

---

### Task 1: TraxKit additions — `RunningTimer` model and `TaskStatus.projectId`

**Files:**
- Create: `TraxKit/Sources/TraxKit/Models/RunningTimer.swift`
- Modify: `TraxKit/Sources/TraxKit/Models/TaskStatus.swift`
- Modify: `TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift`
- Modify: `TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift`

**Interfaces:**
- Produces: `RunningTimer(id: String = "current", taskId: String, startedAt: Date = .now)` — consumed by Task 8 (timer start/stop UI).
- Produces: `TaskStatus(id: String, projectId: String, name: String)` — the `projectId` parameter is new; consumed by Task 7 (status dropdown filtering).

- [ ] **Step 1: Write the failing tests**

Add these two tests to `TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift`, inside the existing `ModelPersistenceTests` struct (after the existing `unscheduledTaskTimeEntryCreatesNoAllocation` test, before the struct's closing `}`):

```swift
    @Test("TaskStatus round-trips")
    func taskStatusRoundTrip() throws {
        let context = try makeContext()
        let status = TaskStatus(id: "s1", projectId: "p1", name: "In Progress")
        context.insert(status)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TaskStatus>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.projectId == "p1")
        #expect(fetched.first?.name == "In Progress")
    }

    @Test("RunningTimer round-trips")
    func runningTimerRoundTrip() throws {
        let context = try makeContext()
        let startedAt = Date(timeIntervalSince1970: 1000)
        let timer = RunningTimer(taskId: "t1", startedAt: startedAt)
        context.insert(timer)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RunningTimer>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "current")
        #expect(fetched.first?.taskId == "t1")
        #expect(fetched.first?.startedAt == startedAt)
    }
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd TraxKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (use the `DEVELOPER_DIR` prefix if plain `swift test` fails with "plugin for module 'SwiftDataMacros' not found" — see `TraxKit/README.md`)
Expected: FAIL to compile — `TaskStatus(id:projectId:name:)` and `RunningTimer` don't exist yet.

- [ ] **Step 3: Add `projectId` to `TaskStatus`**

Replace the full contents of `TraxKit/Sources/TraxKit/Models/TaskStatus.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class TaskStatus {
    @Attribute(.unique) public var id: String
    public var projectId: String
    public var name: String

    public init(id: String, projectId: String, name: String) {
        self.id = id
        self.projectId = projectId
        self.name = name
    }
}
```

- [ ] **Step 4: Create `RunningTimer`**

`TraxKit/Sources/TraxKit/Models/RunningTimer.swift`:

```swift
import Foundation
import SwiftData

/// Singleton row (id is always "current") representing the one timer that
/// can be running at a time. Starting a new timer deletes this row first;
/// that invariant is enforced by the app layer, not the schema.
@Model
public final class RunningTimer {
    @Attribute(.unique) public var id: String
    public var taskId: String
    public var startedAt: Date

    public init(id: String = "current", taskId: String, startedAt: Date = .now) {
        self.id = id
        self.taskId = taskId
        self.startedAt = startedAt
    }
}
```

- [ ] **Step 5: Register `RunningTimer` in the schema**

In `TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift`, change:

```swift
    public static var schema: Schema {
        Schema([
            Project.self,
            TaskStatus.self,
            TraxTask.self,
            Allocation.self,
            TimeEntry.self,
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
        ])
    }
```

- [ ] **Step 6: Run the tests, verify they pass**

Run: `cd TraxKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: All tests PASS (10 total), output pristine.

- [ ] **Step 7: Commit**

```bash
git add TraxKit/Sources/TraxKit/Models/RunningTimer.swift TraxKit/Sources/TraxKit/Models/TaskStatus.swift TraxKit/Sources/TraxKit/Persistence/PersistenceController.swift TraxKit/Tests/TraxKitTests/ModelPersistenceTests.swift
git commit -m "$(cat <<'EOF'
Add RunningTimer model and TaskStatus.projectId

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: TraxApp package scaffold, sample data, minimal launch

**Files:**
- Create: `Package.swift` (repo root)
- Create: `TraxApp/Sources/TraxApp/TraxApp.swift`
- Create: `TraxApp/Sources/TraxApp/SampleData.swift`

**Interfaces:**
- Consumes: `TraxKit` (`Project`, `TraxTask`, `TaskStatus`, `Allocation`, `PersistenceController`).
- Produces: a running `TraxApp` executable with an in-memory, seeded `ModelContainer`, available to every later task's views via `.modelContainer(container)`.

- [ ] **Step 1: Create the root package manifest**

`Package.swift` (repo root, sibling to `TraxKit/`):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraxApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Trax", targets: ["TraxApp"]),
    ],
    dependencies: [
        .package(path: "TraxKit"),
    ],
    targets: [
        .executableTarget(name: "TraxApp", dependencies: ["TraxKit"]),
        .testTarget(name: "TraxAppTests", dependencies: ["TraxApp"]),
    ]
)
```

- [ ] **Step 2: Create the sample data seeder**

`TraxApp/Sources/TraxApp/SampleData.swift`:

```swift
import Foundation
import SwiftData
import TraxKit

enum SampleData {
    @MainActor
    static func seed(into container: ModelContainer) {
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: .now)

        let design = Project(
            id: "p1", name: "Acme Redesign", colorHex: "#4F46E5",
            workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/p1")!
        )
        let launch = Project(
            id: "p2", name: "Product Launch", colorHex: "#059669",
            workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/p2")!
        )
        context.insert(design)
        context.insert(launch)

        let inProgress = TaskStatus(id: "s1", projectId: "p1", name: "In Progress")
        let blocked = TaskStatus(id: "s2", projectId: "p1", name: "Blocked")
        let todo = TaskStatus(id: "s3", projectId: "p2", name: "To Do")
        context.insert(inProgress)
        context.insert(blocked)
        context.insert(todo)

        let homepage = TraxTask(
            id: "t1", projectId: "p1", name: "Design homepage",
            priority: .critical, dueDate: today, statusId: "s1", storyId: "st1"
        )
        let onboarding = TraxTask(
            id: "t2", projectId: "p1", name: "Revise onboarding flow",
            priority: .normal, dueDate: today.addingTimeInterval(86400 * 3),
            statusId: "s2", storyId: "st2"
        )
        let brief = TraxTask(
            id: "t3", projectId: "p1", name: "Write creative brief",
            priority: .none, dueDate: nil, statusId: nil, storyId: "st3"
        )
        let pressRelease = TraxTask(
            id: "t4", projectId: "p2", name: "Draft press release",
            priority: .high, dueDate: today, statusId: "s3", storyId: "st4"
        )
        [homepage, onboarding, brief, pressRelease].forEach { context.insert($0) }

        context.insert(Allocation(id: "a1", taskId: "t1", date: today, scheduledMinutes: 120))
        context.insert(Allocation(id: "a2", taskId: "t4", date: today, scheduledMinutes: 60))
        // t2 and t3 are assigned but have no allocation for today — the
        // mixed scheduled/unscheduled case from SPEC.md.

        try? context.save()
    }
}
```

- [ ] **Step 3: Create the app entry point**

`TraxApp/Sources/TraxApp/TraxApp.swift`:

```swift
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
```

- [ ] **Step 4: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors (an empty `TraxAppTests` target warning is fine).

- [ ] **Step 5: Commit**

```bash
git add Package.swift TraxApp/Sources/TraxApp/TraxApp.swift TraxApp/Sources/TraxApp/SampleData.swift
git commit -m "$(cat <<'EOF'
Scaffold TraxApp executable target with seeded sample data

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Task sort order (TDD)

**Files:**
- Create: `TraxApp/Sources/TraxApp/TaskSorting.swift`
- Test: `TraxApp/Tests/TraxAppTests/TaskSortingTests.swift`

**Interfaces:**
- Consumes: `TraxTask`, `Priority` from `TraxKit`.
- Produces: `TaskSorting.sorted(_ tasks: [TraxTask]) -> [TraxTask]` — consumed by Task 7 (`TaskListView`).

- [ ] **Step 1: Write the failing tests**

`TraxApp/Tests/TraxAppTests/TaskSortingTests.swift`:

```swift
import Testing
import TraxKit
@testable import TraxApp

@Suite("Task sorting")
struct TaskSortingTests {
    @Test("sorts by priority tier, critical first, none last")
    func sortsByPriority() {
        let low = TraxTask(id: "low", projectId: "p", name: "Low", priority: .low, storyId: "s1")
        let critical = TraxTask(id: "crit", projectId: "p", name: "Critical", priority: .critical, storyId: "s2")
        let none = TraxTask(id: "none", projectId: "p", name: "None", priority: .none, storyId: "s3")
        let high = TraxTask(id: "high", projectId: "p", name: "High", priority: .high, storyId: "s4")

        let sorted = TaskSorting.sorted([low, none, critical, high])
        #expect(sorted.map(\.id) == ["crit", "high", "low", "none"])
    }

    @Test("within a priority tier, sorts by due date ascending, no due date last")
    func sortsByDueDateWithinTier() {
        let today = Calendar.current.startOfDay(for: .now)
        let soon = TraxTask(id: "soon", projectId: "p", name: "Soon", priority: .normal, dueDate: today, storyId: "s1")
        let later = TraxTask(id: "later", projectId: "p", name: "Later", priority: .normal, dueDate: today.addingTimeInterval(86400 * 5), storyId: "s2")
        let noDue = TraxTask(id: "noDue", projectId: "p", name: "No due", priority: .normal, storyId: "s3")

        let sorted = TaskSorting.sorted([noDue, later, soon])
        #expect(sorted.map(\.id) == ["soon", "later", "noDue"])
    }

    @Test("priority tier takes precedence over due date")
    func priorityBeatsDueDate() {
        let today = Calendar.current.startOfDay(for: .now)
        let highNoDue = TraxTask(id: "highNoDue", projectId: "p", name: "High, no due", priority: .high, storyId: "s1")
        let normalDueToday = TraxTask(id: "normalDueToday", projectId: "p", name: "Normal, due today", priority: .normal, dueDate: today, storyId: "s2")

        let sorted = TaskSorting.sorted([normalDueToday, highNoDue])
        #expect(sorted.map(\.id) == ["highNoDue", "normalDueToday"])
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `TaskSorting` doesn't exist yet.

- [ ] **Step 3: Implement the comparator**

`TraxApp/Sources/TraxApp/TaskSorting.swift`:

```swift
import Foundation
import TraxKit

enum TaskSorting {
    static func sorted(_ tasks: [TraxTask]) -> [TraxTask] {
        tasks.sorted { lhs, rhs in
            let lhsRank = priorityRank(lhs.priority)
            let rhsRank = priorityRank(rhs.priority)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return dueDateSortsBefore(lhs.dueDate, rhs.dueDate)
        }
    }

    private static func priorityRank(_ priority: Priority) -> Int {
        Priority.allCases.firstIndex(of: priority) ?? Priority.allCases.count
    }

    private static func dueDateSortsBefore(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l < r
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        }
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `TaskSortingTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/TaskSorting.swift TraxApp/Tests/TraxAppTests/TaskSortingTests.swift
git commit -m "$(cat <<'EOF'
Add task sort order (priority tier, then due date)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Duration field validation/revert state machine (TDD)

**Files:**
- Create: `TraxApp/Sources/TraxApp/DurationFieldState.swift`
- Test: `TraxApp/Tests/TraxAppTests/DurationFieldStateTests.swift`

**Interfaces:**
- Consumes: `parseDuration(_:)`, `DurationParseError` from `TraxKit`.
- Produces: `@Observable final class DurationFieldState` with `var text: String`, `private(set) var previewMinutes: Int?`, `private(set) var errorMessage: String?`, `var canSubmit: Bool`, `func validate() -> Int?`, `func reset()` — consumed by Task 9 (`QuickAddTimeField`).

- [ ] **Step 1: Write the failing tests**

`TraxApp/Tests/TraxAppTests/DurationFieldStateTests.swift`:

```swift
import Testing
import TraxKit
@testable import TraxApp

@Suite("Duration field state")
struct DurationFieldStateTests {
    @Test("live preview updates as valid text is typed")
    func livePreview() {
        let state = DurationFieldState()
        state.text = "1h30m"
        #expect(state.previewMinutes == 90)
        #expect(state.canSubmit)
    }

    @Test("invalid text clears the preview but doesn't show an error yet")
    func invalidTextNoErrorWhileTyping() {
        let state = DurationFieldState()
        state.text = "abc"
        #expect(state.previewMinutes == nil)
        #expect(state.errorMessage == nil)
    }

    @Test("validate on invalid input with no prior valid value clears the field")
    func validateInvalidNoPriorValue() {
        let state = DurationFieldState()
        state.text = "abc"
        let result = state.validate()
        #expect(result == nil)
        #expect(state.text == "")
        #expect(state.errorMessage != nil)
    }

    @Test("validate on invalid input reverts to the last valid value")
    func validateInvalidRevertsToLastValid() {
        let state = DurationFieldState()
        state.text = "1h"
        #expect(state.previewMinutes == 60)
        state.text = "1h30zz"
        let result = state.validate()
        #expect(result == nil)
        #expect(state.text == "1h")
        #expect(state.errorMessage != nil)
    }

    @Test("validate on valid input returns the parsed minutes")
    func validateValid() {
        let state = DurationFieldState()
        state.text = "45m"
        let result = state.validate()
        #expect(result == 45)
        #expect(state.errorMessage == nil)
    }

    @Test("exceeding 24h shows the specific error message")
    func exceedsMaxMessage() {
        let state = DurationFieldState()
        state.text = "25h"
        state.validate()
        #expect(state.errorMessage == "Duration can't exceed 24h")
    }

    @Test("reset clears text, preview, and error")
    func resetClearsState() {
        let state = DurationFieldState()
        state.text = "1h"
        state.reset()
        #expect(state.text == "")
        #expect(state.previewMinutes == nil)
        #expect(state.errorMessage == nil)
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `DurationFieldState` doesn't exist yet.

- [ ] **Step 3: Implement the state machine**

`TraxApp/Sources/TraxApp/DurationFieldState.swift`:

```swift
import Foundation
import TraxKit

@Observable
final class DurationFieldState {
    var text: String = "" {
        didSet { handleTextChange() }
    }
    private(set) var previewMinutes: Int?
    private(set) var errorMessage: String?
    private var lastValidText: String?

    var canSubmit: Bool { previewMinutes != nil }

    private func handleTextChange() {
        switch parseDuration(text) {
        case .success(let minutes):
            previewMinutes = minutes
            lastValidText = text
            errorMessage = nil
        case .failure:
            previewMinutes = nil
        }
    }

    /// Call on blur or submit. Returns the minutes to log/add if the
    /// current text is valid. On invalid input, sets `errorMessage` and
    /// reverts `text` to the last valid value (or clears it if none).
    @discardableResult
    func validate() -> Int? {
        switch parseDuration(text) {
        case .success(let minutes):
            errorMessage = nil
            return minutes
        case .failure(let error):
            errorMessage = Self.message(for: error)
            text = lastValidText ?? ""
            return nil
        }
    }

    func reset() {
        text = ""
        previewMinutes = nil
        errorMessage = nil
        lastValidText = nil
    }

    private static func message(for error: DurationParseError) -> String {
        error == .exceedsMax ? "Duration can't exceed 24h" : "Enter a duration like 1h30m"
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `DurationFieldStateTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/DurationFieldState.swift TraxApp/Tests/TraxAppTests/DurationFieldStateTests.swift
git commit -m "$(cat <<'EOF'
Add duration field validation/revert state machine

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Today view toolbar chrome

**Files:**
- Create: `TraxApp/Sources/TraxApp/TodayView.swift`
- Modify: `TraxApp/Sources/TraxApp/TraxApp.swift`

**Interfaces:**
- Produces: `struct TodayView: View` with `@State private var selectedDate: Date` — later tasks (7, 8, 10) modify this file's `body` to add the list, banner, and bottom row.

- [ ] **Step 1: Create `TodayView` with just the toolbar**

`TraxApp/Sources/TraxApp/TodayView.swift`:

```swift
import SwiftUI
import TraxKit

struct TodayView: View {
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Text("Task list coming soon")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 480)
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
                    // Sync is wired up in a future sub-project.
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(true)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Text("Last synced —")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
}

#Preview {
    TodayView()
}
```

- [ ] **Step 2: Point the app entry at `TodayView`**

In `TraxApp/Sources/TraxApp/TraxApp.swift`, replace:

```swift
        WindowGroup {
            Text("Trax — \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                .frame(minWidth: 640, minHeight: 480)
        }
```

with:

```swift
        WindowGroup {
            TodayView()
        }
```

- [ ] **Step 3: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add TraxApp/Sources/TraxApp/TodayView.swift TraxApp/Sources/TraxApp/TraxApp.swift
git commit -m "$(cat <<'EOF'
Add Today view toolbar chrome

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Formatting helpers (TDD for due-date formatting)

**Files:**
- Create: `TraxApp/Sources/TraxApp/Formatting.swift`
- Test: `TraxApp/Tests/TraxAppTests/DueDateFormattingTests.swift`

**Interfaces:**
- Produces: `enum DurationFormatting { static func short(_ minutes: Int) -> String }`, `enum DueDateFormatting { static func short(_ date: Date, relativeTo now: Date) -> String }`, `extension Color { init(hex: String) }` — all consumed by Task 7's views.

- [ ] **Step 1: Write the failing tests**

`TraxApp/Tests/TraxAppTests/DueDateFormattingTests.swift`:

```swift
import Testing
import Foundation
@testable import TraxApp

@Suite("Due date formatting")
struct DueDateFormattingTests {
    private var today: Date { Calendar.current.startOfDay(for: .now) }

    @Test("today formats as 'Today'")
    func formatsToday() {
        #expect(DueDateFormatting.short(today, relativeTo: today) == "Today")
    }

    @Test("within the next 6 days formats as the abbreviated weekday")
    func formatsWithinWeek() {
        let inThreeDays = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        let expectedWeekday = inThreeDays.formatted(.dateTime.weekday(.abbreviated))
        #expect(DueDateFormatting.short(inThreeDays, relativeTo: today) == expectedWeekday)
    }

    @Test("more than 6 days out formats as 'Next wk'")
    func formatsNextWeek() {
        let inTenDays = Calendar.current.date(byAdding: .day, value: 10, to: today)!
        #expect(DueDateFormatting.short(inTenDays, relativeTo: today) == "Next wk")
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `DueDateFormatting` doesn't exist yet.

- [ ] **Step 3: Implement the formatting helpers**

`TraxApp/Sources/TraxApp/Formatting.swift`:

```swift
import Foundation
import SwiftUI

enum DurationFormatting {
    static func short(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }
}

enum DueDateFormatting {
    static func short(_ date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue = calendar.startOfDay(for: date)
        let daysDifference = calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0

        if daysDifference == 0 { return "Today" }
        if daysDifference > 6 { return "Next wk" }
        return startOfDue.formatted(.dateTime.weekday(.abbreviated))
    }
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `DueDateFormattingTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/Formatting.swift TraxApp/Tests/TraxAppTests/DueDateFormattingTests.swift
git commit -m "$(cat <<'EOF'
Add duration/due-date formatting and hex color helpers

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Task list rendering — grouping, rows, status dropdown

**Files:**
- Create: `TraxApp/Sources/TraxApp/TaskListView.swift`
- Create: `TraxApp/Sources/TraxApp/ProjectHeaderRow.swift`
- Create: `TraxApp/Sources/TraxApp/TaskRowView.swift`
- Create: `TraxApp/Sources/TraxApp/StatusDropdown.swift`
- Modify: `TraxApp/Sources/TraxApp/TodayView.swift`

**Interfaces:**
- Consumes: `TaskSorting.sorted(_:)` (Task 3), `DurationFormatting.short(_:)`, `DueDateFormatting.short(_:relativeTo:)`, `Color(hex:)` (Task 6).
- Produces: `TaskListView(selectedDate: Date)`, `TaskRowView(task: TraxTask, date: Date, status: TaskStatus?, statusOptions: [TaskStatus], scheduledMinutes: Int?, loggedMinutes: Int)` — the `date` parameter here is consumed by Task 9 (quick-add) and read by Task 8 for display purposes only (timer start always uses `.now`, not this `date`).

- [ ] **Step 1: Create `StatusDropdown`**

`TraxApp/Sources/TraxApp/StatusDropdown.swift`:

```swift
import SwiftUI
import SwiftData
import TraxKit

struct StatusDropdown: View {
    let task: TraxTask
    let currentStatus: TaskStatus?
    let options: [TaskStatus]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if task.statusId == nil {
            Text("No status")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Status", selection: Binding(
                get: { task.statusId },
                set: { newValue in
                    task.statusId = newValue
                    try? modelContext.save()
                }
            )) {
                ForEach(options, id: \.id) { option in
                    Text(option.name).tag(Optional(option.id))
                }
            }
            .labelsHidden()
            .font(.caption)
        }
    }
}
```

- [ ] **Step 2: Create `ProjectHeaderRow`**

`TraxApp/Sources/TraxApp/ProjectHeaderRow.swift`:

```swift
import SwiftUI
import AppKit
import TraxKit

struct ProjectHeaderRow: View {
    let project: Project
    let scheduledMinutes: Int
    let loggedMinutes: Int

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: project.colorHex))
                .frame(width: 10, height: 10)
            Button {
                NSWorkspace.shared.open(project.workspaceURL)
            } label: {
                HStack(spacing: 4) {
                    Text(project.name)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            Spacer()
            Text("\(DurationFormatting.short(loggedMinutes)) logged of \(DurationFormatting.short(scheduledMinutes)) scheduled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.headline)
    }
}
```

- [ ] **Step 3: Create `TaskRowView`**

`TraxApp/Sources/TraxApp/TaskRowView.swift`:

```swift
import SwiftUI
import AppKit
import TraxKit

struct TaskRowView: View {
    let task: TraxTask
    let date: Date
    let status: TaskStatus?
    let statusOptions: [TaskStatus]
    let scheduledMinutes: Int?
    let loggedMinutes: Int

    var body: some View {
        HStack(spacing: 12) {
            priorityDot
            Button {
                openTaskLink()
            } label: {
                HStack(spacing: 4) {
                    Text(task.name)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .frame(minWidth: 160, alignment: .leading)

            Text(dueLabel)
                .font(.caption)
                .foregroundStyle(task.dueDate == nil ? .secondary : .primary)
                .frame(width: 70, alignment: .leading)

            scheduledLabel
                .frame(width: 120, alignment: .leading)

            Text(DurationFormatting.short(loggedMinutes))
                .font(.caption)
                .frame(width: 70, alignment: .leading)

            StatusDropdown(task: task, currentStatus: status, options: statusOptions)
                .frame(width: 140, alignment: .leading)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var priorityDot: some View {
        Circle()
            .fill(priorityColor ?? Color.clear)
            .frame(width: 8, height: 8)
    }

    private var priorityColor: Color? {
        switch task.priority {
        case .critical: return .red
        case .high: return .orange
        case .normal: return .gray
        case .low: return Color.gray.opacity(0.5)
        case .none: return nil
        }
    }

    private var dueLabel: String {
        guard let dueDate = task.dueDate else { return "No due date" }
        return DueDateFormatting.short(dueDate, relativeTo: .now)
    }

    private var scheduledLabel: some View {
        Group {
            if let scheduledMinutes {
                Text(DurationFormatting.short(scheduledMinutes))
                    .font(.caption)
            } else {
                Text("No time scheduled")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openTaskLink() {
        guard let url = URL(string: "https://app.mavenlink.com/workspaces/\(task.projectId)/stories/\(task.storyId)") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Create `TaskListView`**

`TraxApp/Sources/TraxApp/TaskListView.swift`:

```swift
import SwiftUI
import SwiftData
import TraxKit

struct TaskListView: View {
    let selectedDate: Date

    @Query private var projects: [Project]
    @Query private var tasks: [TraxTask]
    @Query private var allocations: [Allocation]
    @Query private var timeEntries: [TimeEntry]
    @Query private var statuses: [TaskStatus]

    private var groupedTasks: [(project: Project, tasks: [TraxTask])] {
        projects
            .sorted { $0.name < $1.name }
            .map { project in
                let tasksForProject = tasks.filter { $0.projectId == project.id }
                return (project, TaskSorting.sorted(tasksForProject))
            }
            .filter { !$0.tasks.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groupedTasks, id: \.project.id) { group in
                    ProjectHeaderRow(
                        project: group.project,
                        scheduledMinutes: totalScheduled(for: group.project),
                        loggedMinutes: totalLogged(for: group.project)
                    )
                    ForEach(group.tasks, id: \.id) { task in
                        TaskRowView(
                            task: task,
                            date: selectedDate,
                            status: statuses.first { $0.id == task.statusId },
                            statusOptions: statuses.filter { $0.projectId == task.projectId },
                            scheduledMinutes: scheduledMinutes(for: task),
                            loggedMinutes: loggedMinutes(for: task)
                        )
                    }
                }
            }
            .padding()
        }
    }

    private func scheduledMinutes(for task: TraxTask) -> Int? {
        allocations.first { $0.taskId == task.id && $0.date == selectedDate }?.scheduledMinutes
    }

    private func loggedMinutes(for task: TraxTask) -> Int {
        timeEntries.filter { $0.taskId == task.id && $0.date == selectedDate }.reduce(0) { $0 + $1.minutes }
    }

    private func totalScheduled(for project: Project) -> Int {
        tasks.filter { $0.projectId == project.id }
            .compactMap { scheduledMinutes(for: $0) }
            .reduce(0, +)
    }

    private func totalLogged(for project: Project) -> Int {
        tasks.filter { $0.projectId == project.id }
            .map { loggedMinutes(for: $0) }
            .reduce(0, +)
    }
}
```

- [ ] **Step 5: Wire the list into `TodayView`**

In `TraxApp/Sources/TraxApp/TodayView.swift`, replace:

```swift
            Divider()
            Text("Task list coming soon")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

with:

```swift
            Divider()
            TaskListView(selectedDate: selectedDate)
```

- [ ] **Step 6: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 7: Commit**

```bash
git add TraxApp/Sources/TraxApp/TaskListView.swift TraxApp/Sources/TraxApp/ProjectHeaderRow.swift TraxApp/Sources/TraxApp/TaskRowView.swift TraxApp/Sources/TraxApp/StatusDropdown.swift TraxApp/Sources/TraxApp/TodayView.swift
git commit -m "$(cat <<'EOF'
Render grouped, sorted task list with status dropdown and deep links

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Running timer — elapsed-time math (TDD) and banner/start-button wiring

**Files:**
- Create: `TraxApp/Sources/TraxApp/RunningTimerLogic.swift`
- Test: `TraxApp/Tests/TraxAppTests/RunningTimerLogicTests.swift`
- Create: `TraxApp/Sources/TraxApp/RunningTimerBanner.swift`
- Modify: `TraxApp/Sources/TraxApp/TaskRowView.swift`
- Modify: `TraxApp/Sources/TraxApp/TodayView.swift`

**Interfaces:**
- Produces: `RunningTimerLogic.elapsedMinutes(from startedAt: Date, to now: Date) -> Int` — consumed by `RunningTimerBanner`.
- Consumes: `RunningTimer` (Task 1).

- [ ] **Step 1: Write the failing test for elapsed-minutes rounding**

`TraxApp/Tests/TraxAppTests/RunningTimerLogicTests.swift`:

```swift
import Testing
import Foundation
@testable import TraxApp

@Suite("Running timer logic")
struct RunningTimerLogicTests {
    @Test("rounds up at 30 seconds or more")
    func roundsUpAtHalfMinute() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(90) // 1.5 minutes
        #expect(RunningTimerLogic.elapsedMinutes(from: start, to: now) == 2)
    }

    @Test("rounds down under 30 seconds")
    func roundsDownUnderHalfMinute() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(29)
        #expect(RunningTimerLogic.elapsedMinutes(from: start, to: now) == 0)
    }

    @Test("zero elapsed time is zero minutes")
    func zeroElapsed() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(RunningTimerLogic.elapsedMinutes(from: start, to: start) == 0)
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `RunningTimerLogic` doesn't exist yet.

- [ ] **Step 3: Implement the elapsed-time helper**

`TraxApp/Sources/TraxApp/RunningTimerLogic.swift`:

```swift
import Foundation

enum RunningTimerLogic {
    static func elapsedMinutes(from startedAt: Date, to now: Date) -> Int {
        Int((now.timeIntervalSince(startedAt) / 60).rounded())
    }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `RunningTimerLogicTests` PASS.

- [ ] **Step 5: Create `RunningTimerBanner`**

`TraxApp/Sources/TraxApp/RunningTimerBanner.swift`:

```swift
import SwiftUI
import SwiftData
import TraxKit

struct RunningTimerBanner: View {
    @Query private var runningTimers: [RunningTimer]
    @Query private var tasks: [TraxTask]
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var now: Date = .now
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var runningTimer: RunningTimer? { runningTimers.first }

    private var task: TraxTask? {
        guard let runningTimer else { return nil }
        return tasks.first { $0.id == runningTimer.taskId }
    }

    private var project: Project? {
        guard let task else { return nil }
        return projects.first { $0.id == task.projectId }
    }

    private var elapsed: TimeInterval {
        guard let runningTimer else { return 0 }
        return now.timeIntervalSince(runningTimer.startedAt)
    }

    var body: some View {
        if let runningTimer, let task {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(task.name)
                        .font(.headline)
                }
                Spacer()
                Text(elapsedLabel)
                    .font(.system(.body, design: .monospaced))
                Button("Stop") {
                    stop(runningTimer)
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.15))
            .onReceive(ticker) { tick in now = tick }
        }
    }

    private var elapsedLabel: String {
        let totalSeconds = max(0, Int(elapsed))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func stop(_ runningTimer: RunningTimer) {
        let elapsedMinutes = RunningTimerLogic.elapsedMinutes(from: runningTimer.startedAt, to: now)
        if elapsedMinutes > 0 {
            let entry = TimeEntry(
                taskId: runningTimer.taskId,
                date: Calendar.current.startOfDay(for: .now),
                minutes: elapsedMinutes
            )
            modelContext.insert(entry)
        }
        modelContext.delete(runningTimer)
        try? modelContext.save()
    }
}
```

- [ ] **Step 6: Add a start button to `TaskRowView`**

In `TraxApp/Sources/TraxApp/TaskRowView.swift`, add these two properties right after the existing `let loggedMinutes: Int` property:

```swift
    @Query private var runningTimers: [RunningTimer]
    @Environment(\.modelContext) private var modelContext
```

Then, in the `body`'s `HStack`, insert a start button as the very first element, before `priorityDot`:

```swift
            Button {
                startTimer()
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
```

Finally, add these two computed members near the bottom of the `TaskRowView` struct, alongside the other private helpers:

```swift
    private var isRunning: Bool {
        runningTimers.first?.taskId == task.id
    }

    private func startTimer() {
        if let existing = runningTimers.first {
            modelContext.delete(existing)
        }
        modelContext.insert(RunningTimer(taskId: task.id, startedAt: .now))
        try? modelContext.save()
    }
```

Note: `TraxRowView` needs `import SwiftData` added alongside its existing `import SwiftUI` and `import AppKit` for `@Query`/`@Environment(\.modelContext)` to resolve.

- [ ] **Step 7: Wire the banner into `TodayView`**

In `TraxApp/Sources/TraxApp/TodayView.swift`, replace:

```swift
            Divider()
            TaskListView(selectedDate: selectedDate)
```

with:

```swift
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
```

- [ ] **Step 8: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 9: Commit**

```bash
git add TraxApp/Sources/TraxApp/RunningTimerLogic.swift TraxApp/Tests/TraxAppTests/RunningTimerLogicTests.swift TraxApp/Sources/TraxApp/RunningTimerBanner.swift TraxApp/Sources/TraxApp/TaskRowView.swift TraxApp/Sources/TraxApp/TodayView.swift
git commit -m "$(cat <<'EOF'
Add running timer banner and per-row start control

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Per-row quick-add time entry

**Files:**
- Create: `TraxApp/Sources/TraxApp/QuickAddTimeField.swift`
- Modify: `TraxApp/Sources/TraxApp/TaskRowView.swift`

**Interfaces:**
- Consumes: `DurationFieldState` (Task 4).
- Produces: `QuickAddTimeField(state: DurationFieldState, placeholder: String, submitLabel: String, onSubmit: (Int) -> Void)` — also consumed by Task 10 (`AddTimeRow`).

- [ ] **Step 1: Create `QuickAddTimeField`**

`TraxApp/Sources/TraxApp/QuickAddTimeField.swift`:

```swift
import SwiftUI

struct QuickAddTimeField: View {
    @Bindable var state: DurationFieldState
    let placeholder: String
    let submitLabel: String
    let onSubmit: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $state.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { submit() }

                if let previewMinutes = state.previewMinutes {
                    Text("= \(previewMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(submitLabel) { submit() }
                    .disabled(!state.canSubmit)
            }
            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        if let minutes = state.validate() {
            onSubmit(minutes)
            state.reset()
        }
    }
}
```

- [ ] **Step 2: Add the quick-add toggle to `TaskRowView`**

In `TraxApp/Sources/TraxApp/TaskRowView.swift`, add these two properties alongside the existing `@Query`/`@Environment` properties added in Task 8:

```swift
    @State private var isAddingTime = false
    @State private var durationFieldState = DurationFieldState()
```

Replace the `body`'s top-level `HStack { ... }` wrapper — currently the entire row is one `HStack(spacing: 12) { ... }` inside `.padding(.vertical, 4)` — with a `VStack` containing that same `HStack` (with one addition inside it) plus a conditional quick-add field below it:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    startTimer()
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                priorityDot
                Button {
                    openTaskLink()
                } label: {
                    HStack(spacing: 4) {
                        Text(task.name)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .frame(minWidth: 160, alignment: .leading)

                Text(dueLabel)
                    .font(.caption)
                    .foregroundStyle(task.dueDate == nil ? .secondary : .primary)
                    .frame(width: 70, alignment: .leading)

                scheduledLabel
                    .frame(width: 120, alignment: .leading)

                Text(DurationFormatting.short(loggedMinutes))
                    .font(.caption)
                    .frame(width: 70, alignment: .leading)

                StatusDropdown(task: task, currentStatus: status, options: statusOptions)
                    .frame(width: 140, alignment: .leading)

                Button {
                    isAddingTime.toggle()
                    if !isAddingTime { durationFieldState.reset() }
                } label: {
                    Image(systemName: isAddingTime ? "xmark" : "plus")
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if isAddingTime {
                QuickAddTimeField(
                    state: durationFieldState,
                    placeholder: "1h30m",
                    submitLabel: "Log"
                ) { minutes in
                    logTime(minutes)
                    isAddingTime = false
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }
```

This replaces the entire previous `body` implementation (the one from Task 7's Step 3, as modified by Task 8's Step 6) — it already includes the start-timer button from Task 8, so nothing from that step is lost.

Add this new private method alongside the others (e.g. after `startTimer()`):

```swift
    private func logTime(_ minutes: Int) {
        let entry = TimeEntry(taskId: task.id, date: date, minutes: minutes)
        modelContext.insert(entry)
        try? modelContext.save()
    }
```

- [ ] **Step 3: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add TraxApp/Sources/TraxApp/QuickAddTimeField.swift TraxApp/Sources/TraxApp/TaskRowView.swift
git commit -m "$(cat <<'EOF'
Add per-row quick-add time entry

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Add-time-to-new-task row (bottom of list)

**Files:**
- Create: `TraxApp/Sources/TraxApp/AddTimeRow.swift`
- Modify: `TraxApp/Sources/TraxApp/TodayView.swift`

**Interfaces:**
- Consumes: `QuickAddTimeField` (Task 9), `DurationFieldState` (Task 4).
- Produces: `AddTimeRow(date: Date)`.

- [ ] **Step 1: Create `AddTimeRow`**

`TraxApp/Sources/TraxApp/AddTimeRow.swift`:

```swift
import SwiftUI
import SwiftData
import TraxKit

struct AddTimeRow: View {
    let date: Date

    @Query private var projects: [Project]
    @Query private var tasks: [TraxTask]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProjectId: String?
    @State private var taskQuery: String = ""
    @State private var selectedTaskId: String?
    @State private var durationFieldState = DurationFieldState()

    private var tasksForSelectedProject: [TraxTask] {
        guard let selectedProjectId else { return [] }
        let base = tasks.filter { $0.projectId == selectedProjectId }
        guard !taskQuery.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(taskQuery) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Project", selection: $selectedProjectId) {
                Text("Choose a project").tag(String?.none)
                ForEach(projects, id: \.id) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .frame(width: 160)
            .onChange(of: selectedProjectId) {
                selectedTaskId = nil
                taskQuery = ""
            }

            if selectedProjectId != nil {
                TextField("Search tasks", text: $taskQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                Picker("Task", selection: $selectedTaskId) {
                    Text("Choose a task").tag(String?.none)
                    ForEach(tasksForSelectedProject, id: \.id) { task in
                        Text(task.name).tag(Optional(task.id))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            QuickAddTimeField(
                state: durationFieldState,
                placeholder: "1h30m",
                submitLabel: "Add"
            ) { minutes in
                addTime(minutes)
            }
        }
        .padding()
    }

    private func addTime(_ minutes: Int) {
        guard let selectedTaskId else { return }
        let entry = TimeEntry(taskId: selectedTaskId, date: date, minutes: minutes)
        modelContext.insert(entry)
        try? modelContext.save()
        durationFieldState.reset()
        self.selectedTaskId = nil
        taskQuery = ""
    }
}
```

- [ ] **Step 2: Wire the row into `TodayView`**

In `TraxApp/Sources/TraxApp/TodayView.swift`, replace:

```swift
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
```

with:

```swift
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
            Divider()
            AddTimeRow(date: selectedDate)
```

- [ ] **Step 3: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add TraxApp/Sources/TraxApp/AddTimeRow.swift TraxApp/Sources/TraxApp/TodayView.swift
git commit -m "$(cat <<'EOF'
Add bottom add-time-to-new-task row

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** Toolbar/day-nav/sync-button/last-synced chrome — Task 5. Running timer banner, start/stop, timer-tied-to-now — Task 8. Grouped/sorted task list, priority dot, links, due/scheduled/logged columns, status dropdown — Tasks 6–7. Quick-add per row — Task 9. Add-time-to-new-task row with project→task-search→duration→Add — Task 10. Duration parser reuse and its inline-error/revert-to-last-valid UI behavior — Task 4 (state machine) + Task 9/10 (wiring). `RunningTimer`/`TaskStatus.projectId` model additions — Task 1. Mixed scheduled/unscheduled tasks in one list — covered by `SampleData` (Task 2) and `TaskListView`'s single unfiltered task list (Task 7), matching Foundation's "Task = assignment" design. Sync push/pull, conflict resolution, staleness banner, and auth are explicitly out of scope (sub-projects #3/#4).
- **Placeholder scan:** none found — every step has concrete, complete code.
- **Type consistency:** `TraxTask`, `Priority`, `TaskStatus`, `Allocation`, `TimeEntry`, `RunningTimer`, `PersistenceController` all used exactly as Foundation (already merged) defines them, with `TaskStatus`'s new `projectId` parameter threaded consistently from Task 1 onward. `TaskRowView`'s `date` parameter (introduced in Task 7) is consumed by Task 9's `logTime` and matches `TaskListView`'s `selectedDate` pass-through. `DurationFieldState` (Task 4) and `QuickAddTimeField` (Task 9) share the same `canSubmit`/`previewMinutes`/`errorMessage`/`validate()`/`reset()` surface used identically by Task 9's per-row wiring and Task 10's `AddTimeRow`. `RunningTimerLogic.elapsedMinutes` (Task 8) is used identically by `RunningTimerBanner.stop`.
