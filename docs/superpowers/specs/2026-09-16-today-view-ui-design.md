# Today view UI — design spec

Sub-project 2 of 4 for Trax (native macOS Kantata time tracker; see top-level `SPEC.md` for the full product spec, and `docs/superpowers/specs/2026-09-16-foundation-design.md` for the domain-model layer this builds on). This covers the SwiftUI app target and the entire Today view: toolbar, running timer, task list, time entry, and status editing — all running against seeded sample data, with no networking yet.

## Goals

- Stand up a runnable SwiftUI app (`TraxApp`) on top of the already-merged `TraxKit` package.
- Implement the full Today view UI and interaction model described in `SPEC.md` §§ Screen: today view, Time entry, Status, Project/task links.
- Resolve two gaps the product spec left open: how a running timer starts, and how logging time relates to sync (see Decisions below).

## Non-goals

- No Kantata API client, no OAuth (#3).
- No real sync — the sync button exists in the toolbar per spec layout but is inert; push/pull and conflict resolution are #4.
- No first-launch auth screen — `TodayView` is the app's root view for this sub-project.
- No `.xcodeproj` / Xcode project generation (see Platform below).

## Decisions made during brainstorming (resolving spec gaps)

1. **Starting a timer:** each task row gets a start/play control (in addition to quick-add). Starting a timer on one task stops any other running timer first — only one runs at a time, consistent with there being a single timer banner.
2. **Stopping a timer:** computes elapsed minutes (rounded to the nearest minute) and creates a local `TimeEntry` with `synced: false` — exactly like quick-add, just sourced from the clock instead of typed text. If elapsed rounds to 0 minutes, no entry is created. Nothing is pushed to Kantata on stop; that only happens via a real sync (#4). This is consistent with the product spec's existing "staged until sync" model for logged time and status changes.
3. **Timer persistence:** the running timer's task and start time are persisted in SwiftData (not just in-memory), so quitting and relaunching the app mid-timer resumes the same running timer rather than losing it.

## Platform

No Xcode GUI is available in this environment. Rather than hand-writing or generating a `.xcodeproj` (e.g. via `xcodegen`, which would need installing and maintaining a `project.yml`), `TraxApp` is a plain Swift Package executable target with a SwiftUI `App` entry point. This is fully buildable, runnable (`swift run`), and testable (`swift test`) from the command line, and Xcode can open and run a `Package.swift` folder directly without a `.xcodeproj` — so this doesn't block opening the project in Xcode later.

## Package & target structure

New root-level `Package.swift` (sibling to the existing `TraxKit/` directory), depending on `TraxKit` as a local path package:

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

## New TraxKit additions

Small, additive changes to the already-merged Foundation package — no redesign of what's there.

### `RunningTimer` (new model)
- `id: String` — constant `"current"`; this is a singleton row.
- `taskId: String`
- `startedAt: Date`

Only one `RunningTimer` row exists at a time; starting a new timer deletes the existing row first. This is an app-level invariant (not schema-enforced), documented the same way as `Allocation`'s `(taskId, date)` uniqueness invariant.

### `TaskStatus.projectId` (new field on an existing model)
Foundation's `TaskStatus` had no project/workspace scoping. The status dropdown needs to show only the status options valid for a given task's workspace (`SPEC.md` § Status: "pulled live from the task's actual per-workspace status set"), so `TaskStatus` gains a `projectId: String` field ("workspace" and "project" are the same concept in Kantata's data model, per `SPEC.md` § Project/task links' URL pattern).

## View architecture

One file, one responsibility, under `TraxApp/Sources/TraxApp/`:

- **`TraxApp.swift`** — `@main App`. Builds the `ModelContainer` (in-memory for this sub-project) and seeds sample data on launch.
- **`TodayView.swift`** — root view. Toolbar (day nav `< date >`, sync button, "Last synced X ago" caption), the pinned `RunningTimerBanner` (always visible regardless of day), `TaskListView`, and the fixed `AddTimeRow` at the bottom.
- **`RunningTimerBanner.swift`** — reads the singleton `RunningTimer` via `@Query`. An `@Observable RunningTimerClock` drives a 1-second UI tick for the live HH:MM:SS display, computed from `Date.now - startedAt` rather than persisting every second.
- **`TaskListView.swift`** — groups tasks by project, renders `ProjectHeaderRow` + sorted `TaskRowView` per project, computes per-project subtotals.
- **`ProjectHeaderRow.swift`** — colored dot, project name (deep link), subtotal.
- **`TaskRowView.swift`** — priority dot, task name (deep link), due date, scheduled/logged durations, `StatusDropdown`, start/stop timer control, quick-add `+`/`×` toggle with `QuickAddTimeField`.
- **`QuickAddTimeField.swift`** — shared duration-input component: live-previews parsed minutes via `TraxKit.parseDuration`, shows an inline error and reverts to the last valid value on invalid blur/submit. Reused by the per-row quick-add and the bottom `AddTimeRow`.
- **`AddTimeRow.swift`** — project dropdown → task search scoped to that project → `QuickAddTimeField` → "Add" button.
- **`StatusDropdown.swift`** — renders only when the task has a `statusId`; options are `TaskStatus` rows matching the task's `projectId`. Changing status is a local field change only (no side effects), staged the same way as time entries.
- **`SampleData.swift`** — seed data: a handful of projects, tasks (mixed scheduled/unscheduled), allocations, and per-project status sets. No time entries, no running timer, so the app starts from a clean day.

## Sort order

Priority tier (critical → high → normal → low → none-last) then due date ascending (no-due-date last within its tier), per `SPEC.md` § Sort order. Implemented as a pure, unit-testable comparator in `TraxAppTests` rather than a SwiftData query sort — "no priority"/"no due date" need custom last-place ordering that SwiftData predicates/sort descriptors can't express directly against optional fields with this tie-breaking.

## Testing plan

- **`TraxAppTests`**: the sort comparator (all priority/due-date tie-breaking cases from the spec), and the quick-add field's validation/revert state machine (valid → invalid → reverts to last valid; valid → invalid → empty when no prior valid value existed).
- **Build verification**: `swift build` from the repo root confirms the app target compiles against `TraxKit`. Visual/interactive verification (does the timer actually tick, does the list actually render as expected) is not possible in this sandboxed environment — running (`swift run`) or opening in Xcode to eyeball it is left to you.

## Open items / carried forward

- Sync button is present but inert until #4.
- Kantata deep-link URL pattern still unverified (`SPEC.md` § Open items) — unchanged by this sub-project.
- Auth/first-launch screen is #3; this sub-project's `TraxApp.swift` goes straight to `TodayView`.
