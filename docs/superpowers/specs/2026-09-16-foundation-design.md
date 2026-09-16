# Foundation — design spec

Sub-project 1 of 4 for Trax (native macOS Kantata time tracker; see top-level `SPEC.md` for the full product spec). This covers the project scaffold, domain models, local persistence, and the duration parser — the dependency-free groundwork the UI (#2), auth/API client (#3), and sync engine (#4) all build on.

## Goals

- Stand up the Xcode project and a separately-testable Swift package for domain logic.
- Define the local data model needed to render the Today view and support time entry, without speculating on sync/conflict-resolution internals (that's sub-project #4).
- Implement and fully test the duration parser described in `SPEC.md` § Duration parser.

## Non-goals

- No networking, no Kantata API client (#3).
- No SwiftUI views (#2).
- No sync/conflict-tracking fields beyond the minimum needed to distinguish a locally-created, not-yet-synced time entry (#4 owns the rest of that design).

## Platform & tooling

- macOS 14+ target (enables SwiftData).
- App: `Trax`, bundle id `com.jumpingjackrabbit.trax`.
- Swift Testing (`@Test` / `#expect`) for unit tests.

## Project structure

- Xcode project `Trax.app` — app target stays thin; it will hold SwiftUI views once #2 starts.
- Local Swift package `TraxKit`, added as a local package dependency of the app target, containing:
  - Domain models (SwiftData `@Model` classes)
  - Duration parser
  - Persistence stack (SwiftData `ModelContainer` setup)
  - Unit tests for the above

Rationale: keeping domain logic in a package the app target merely imports means it's independently buildable/testable, and later sub-projects (UI, API client, sync) each get a clear boundary to depend on without reaching into app-target internals.

## Domain models (SwiftData)

All IDs are Kantata's own resource IDs (stored as `String`) unless noted otherwise.

### `Project`
- `id: String`
- `name: String`
- `colorHex: String`
- `workspaceURL: URL` — base URL for deep links (see `SPEC.md` § Project/task links)

### `TaskStatus`
- `id: String`
- `name: String`
- Workspace-scoped — pulled live from Kantata's Task Statuses per Task Status Set, never hardcoded.

### `Task`
- `id: String`
- `projectId: String`
- `name: String`
- `priority: Priority` — enum `{ critical, high, normal, low, none }`
- `dueDate: Date?`
- `statusId: String?` — nil means "No status" (spec: dropdown only renders if a status is actually assigned)
- `storyId: String` — for building the task deep link

A `Task` row existing locally **is** the user's assignment to it (created from Kantata's Assignments resource). It is not conditioned on having any allocation — that's what makes "mixed scheduled/unscheduled" tasks in the same list possible (`SPEC.md` § Mixed scheduled / unscheduled tasks).

### `Allocation` (Daily Scheduled Hours / Story Allocation Days)
- `id: String`
- `taskId: String`
- `date: Date` (day granularity)
- `scheduledMinutes: Int`

One row per task per day that actually has scheduled hours. No row for a given (task, date) means "No time scheduled" for that day — this is a computed absence, not a stored flag.

### `TimeEntry`
- `id: String` — local `UUID` string until synced, then replaced with the Kantata-assigned ID
- `taskId: String`
- `date: Date` (day granularity)
- `minutes: Int`
- `synced: Bool`
- `createdAt: Date`

Logging time never creates or touches an `Allocation` row (spec: "creates a time entry without ever creating an allocation").

### Computed, not stored
- **Scheduled (for a task/day)**: look up `Allocation` for `(taskId, date)`; absence → "No time scheduled".
- **Logged (for a task/day)**: sum of `TimeEntry.minutes` for `(taskId, date)`.
- **Project subtotal**: sum of scheduled / logged across the project's tasks for the day.

## Duration parser

Pure function in `TraxKit`, no UI or persistence dependency:

```swift
enum DurationParseError: Error, Equatable {
    case empty
    case unparseable
    case negative
    case minutesOutOfRange   // Xh Ym form, minutes >= 60
    case exceedsMax          // > 1440 minutes
}

func parseDuration(_ input: String) -> Result<Int, DurationParseError>
```

Implements, in priority order, exactly the grammar from `SPEC.md` § Duration parser:
1. `2h45m` / `2h 45m` → hours + minutes
2. `2h` → hours only
3. `45m` → minutes only
4. `2:45` (h:mm, minutes portion 0–59)
5. Bare number (int/float, no unit) → treated as hours, rounded to nearest whole minute

Rules encoded directly as parser behavior: unit letters (case-insensitive) anywhere in the string take priority over bare-number-as-hours; reject empty/unparseable/negative/minutes≥60-in-Xh-Ym-form/totals over 1440 minutes.

This function owns parsing/validation only — the inline-error and revert-to-last-valid-value UI behavior described in the spec belongs to sub-project #2.

## Testing plan

- **Duration parser**: table-driven `@Test` cases covering every accepted form and every rejection rule listed above, taken directly from the spec's examples (`2h45m`, `2h 45m`, `2h`, `45m`, `2:45`, `1` → 60, `0.75` → 45, `1.5` → 90, plus `1h90m`, negative, empty, unparseable, >1440).
- **Models/persistence**: round-trip tests — insert a `Project`/`Task`/`Allocation`/`TimeEntry` into an in-memory `ModelContainer`, fetch back, assert field equality; a test confirming a `TimeEntry` for an unscheduled task does not create an `Allocation`.

## Open questions carried forward (not blocking this sub-project)

- Sync/conflict-tracking model shape — deferred to sub-project #4.
- Kantata deep-link URL pattern still needs verification (`SPEC.md` § Open items) — `Project.workspaceURL` / `Task.storyId` are named generically enough to not need changes once confirmed.
