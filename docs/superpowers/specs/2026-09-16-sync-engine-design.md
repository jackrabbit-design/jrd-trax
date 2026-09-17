# Sync engine — design spec

Sub-project 4 of 4 for Trax (native macOS Kantata time tracker; see top-level `SPEC.md` for the full product spec). This covers manual push/pull sync, per-field conflict resolution, the staleness banner, and the failure toast — the final piece that wires real Kantata data into the app the other three sub-projects built.

## Goals

- Implement manual (button-triggered, no auto-sync) push/pull sync per `SPEC.md` § Sync: push logged time entries and status changes; pull newly-assigned tasks and updated schedules/allocations.
- Implement per-field conflict resolution per `SPEC.md` § Sync's Conflict resolution subsection, resolving the "field (status, scheduled time, logged time, etc.)" language against what's actually bidirectionally editable in this app's data model (see Decisions below).
- Implement the dimming/disabling sync-in-progress overlay, the staleness banner (>10h since last sync), and the failure toast, all per spec.
- Update `TodayView`'s toolbar to make the sync button and "Last synced X ago" caption (both inert placeholders since sub-project #2) actually work.

## Non-goals

- No automatic/interval sync — manual only, per spec.
- No rebuild of the sign-in flow. An `unauthorized` error during sync surfaces as a plain failure (toast + Retry), not an automatic return to the first-launch screen.
- No archival/removal of tasks that become unassigned server-side — see Decisions.
- No token refresh (unchanged from sub-project #3 — Kantata tokens don't expire, only get revoked).

## Decisions made during brainstorming (resolving spec ambiguity)

1. **Conflict resolution scope.** `SPEC.md`'s conflict section lists "status, scheduled time, logged time, etc." as example conflicting fields, but only `status` is genuinely bidirectional in this app: scheduled time (`Allocation`) is pull-only (never locally edited), and logged time (`TimeEntry`) is create-only (never edited after logging — there's no "change a past time entry" UI anywhere in the app). So conflict detection/resolution is built for `status` only. The per-conflict UI (`ConflictResolutionView`) is generic over "a named field with a local value and a server value," so extending it to a future bidirectional field later doesn't require a rewrite — it just isn't speculatively built out now.
2. **Revoked/invalid token during sync.** Surfaces as a normal sync failure (red toast, "Your Kantata connection needs to be reconnected," Retry + dismiss) rather than automatically clearing the token and routing back to the first-launch screen. Keeps this sub-project scoped to sync itself.
3. **Unassigned tasks during pull.** A task no longer present in the pulled Assignments list is left alone locally (not deleted), to avoid orphaning its logged-time history (`TimeEntry` rows reference `taskId` with no cascade delete, per `TraxKit/README.md`'s documented limitation). Archiving/removing it is an open item, not solved here.

## New TraxKit additions

Small, additive changes to the already-merged `TraxKit` package.

### `TraxTask.syncedStatusId` (new field on an existing model)
- `syncedStatusId: String?` — the baseline: the last-known-server value of `statusId` as of the most recent successful sync. `nil` means "never synced" (no baseline to compare against, so no conflict check is possible or needed yet).
- This is the local-vs-server baseline field flagged as missing in sub-project #3's final review — without it, "changed both locally and on the server since last sync" (per `SPEC.md`'s conflict trigger) can't be determined; only "differs from what we currently see" can.

### `SyncState` (new model, singleton like `RunningTimer`)
- `id: String` (constant `"current"`), `lastSyncedAt: Date?`.
- Drives the "Last synced X ago" caption and the >10h staleness banner.

## KantataAPI additions

### `KantataAPIClient.fetchDailyScheduledHours(from:to:)`
- The existing (unbounded) `fetchDailyScheduledHours()` gains `from: String, to: String` (ISO date strings, matching the DTO's existing string-date convention) parameters. Pulling truly all historical allocations forever isn't practical; this sub-project bounds the pull to a window around "today." The exact window and whether Kantata's real API even supports this kind of filtering is unverified — flagged as an open item, consistent with the DTOs' already-flagged placeholder-shape assumption.

### `KantataAPIClient.createStoryStateChange(storyId:statusId:)`
- Pushes a status change. Kantata's resource list (`SPEC.md` § Relevant Kantata API resources) includes "Story State Changes" under Tasks — this is the natural mapping for "push a status change," as opposed to a generic story-update endpoint.

## Sync algorithm

Two-phase, so conflict resolution can pause mid-sync without the engine needing to manage its own suspended continuation:

### Phase 1: `SyncEngine.prepareSync() async throws -> SyncPreparation`
- Fetches the remote snapshot: task statuses, status sets, assignments, and daily scheduled hours (bounded window) via `KantataAPIClient`. Read-only — no local mutation.
- For each local `TraxTask`, compares `statusId` (current, possibly locally-edited) against `syncedStatusId` (baseline) against the freshly-fetched remote status for that task:
  - Local unchanged from baseline → no conflict, remote value (if different) will simply be adopted during apply.
  - Remote unchanged from baseline → no conflict, local value (if different) will simply be pushed during apply.
  - Both changed from baseline, and local ≠ remote → **conflict**.
- Returns a `SyncPreparation` bundling the fetched snapshot plus a `[SyncConflict]` list (task id, task name, local status name, server status name).
- Any network/HTTP error here aborts the whole attempt before anything is touched.

### Phase 2: `SyncEngine.applySync(_ preparation: SyncPreparation, resolutions: [String: ConflictResolution]) async throws`
- For each conflict, `resolutions[taskId]` says `.keepMine` (push local value) or `.useKantatas` (discard local edit, adopt server value) — required for every conflict; the caller (UI) doesn't invoke this phase until all are chosen.
- Pushes: every local `TimeEntry` with `synced == false` (via `createTimeEntry`, marking `synced = true` on success); every `TraxTask` whose current `statusId` differs from its baseline and wasn't just overwritten by a `.useKantatas` resolution (via `createStoryStateChange`).
- Pulls/upserts: `TaskStatus`/`StatusSet` rows (replace by id), `Allocation` rows within the fetched window (add/update/remove to match the server snapshot for that window), new `TraxTask` rows from assignments not already present locally (existing tasks' `name`/`priority`/`dueDate` are refreshed from the pull, but `statusId` is left alone — that field is locally/conflict-managed, not blindly overwritten by a pull).
- Updates every task's `syncedStatusId` baseline to its now-confirmed status, and `SyncState.lastSyncedAt` to `.now`.
- A push failure partway through (e.g. one time entry POST fails) doesn't rewind already-succeeded pushes — it collects what failed and surfaces a summarized failure toast; the caller can retry, and only the still-unsynced/unresolved items are attempted again.

## UI

### `SyncController` (`@Observable`, orchestrates `SyncEngine`)
- Phases: `.idle`, `.syncing`, `.conflicts([SyncConflict])`, `.failed(message)`.
- `startSync()` calls `prepareSync()`; if no conflicts, immediately calls `applySync(resolutions: [:])`; if conflicts exist, transitions to `.conflicts` and waits for the UI to call `resolveConflicts(_:)`, which then calls `applySync`.

### Toolbar wiring (`TodayView`)
- The sync button (inert since #2) now calls `syncController.startSync()`.
- The "Last synced —" caption (inert since #2) now reads `SyncState.lastSyncedAt`, formatted relative to now, ticking similarly to `RunningTimerBanner`'s existing live-update pattern.
- Amber staleness banner: shown (non-blocking, coexists with normal use) when `lastSyncedAt` is `nil` or more than 10 hours old, with its own "Sync now" shortcut.

### Sync-in-progress overlay
- `.disabled(syncController.isSyncing)` plus a dimming `.overlay` applied once at `TodayView`'s root — SwiftUI's `.disabled` modifier propagates to every descendant control automatically, so day nav, the sync button, status dropdowns, and quick-add all get disabled without touching each of those files individually. Centered spinner + "Syncing with Kantata…" label per spec.

### `ConflictResolutionView` (blocking modal)
- One row per conflict, no default selection, "Choose one" hint on unresolved rows, "Apply and continue sync" disabled until every row has a choice, "Cancel sync" aborts the whole attempt (returns to `.idle`, nothing pushed or pulled).

### Failure toast
- Red, non-blocking banner naming the actual reason, inline "Retry" (calls `startSync()` again) plus a dismiss control, per spec.

## Testing plan

- **TraxKit**: round-trip test for `TraxTask.syncedStatusId` and `SyncState`, matching the existing `ModelPersistenceTests` pattern.
- **KantataAPI**: `fetchDailyScheduledHours(from:to:)` and `createStoryStateChange(storyId:statusId:)` tested against a stub `HTTPTransport`, matching the existing `KantataAPIClientTests` pattern.
- **Conflict detection**: pure, standalone `detectConflicts(tasks:remoteStatuses:) -> [SyncConflict]` function, fully unit-tested (local-only change, remote-only change, both-changed-same-value, both-changed-different-value, never-synced-baseline-nil) with no networking/UI dependency — same pattern as sub-project #2's `TaskSorting`.
- **`SyncEngine`**: both phases tested against a stub `HTTPTransport` (reusing the sub-project #3 pattern) and a real in-memory `ModelContainer`, covering the push/pull/conflict/baseline-update behaviors above.
- **`SyncController`**: state-machine transitions tested against a fake/stubbed engine, matching sub-project #3's `AuthFlowController` test pattern.
- UI wiring (toolbar, overlay, modal, toast) is build-verified only, consistent with how sub-projects #2/#3 tested SwiftUI glue around already-tested logic.

## Open items / carried forward

- `fetchDailyScheduledHours`'s date-range filtering support is unverified against Kantata's real API, same as the DTOs' placeholder shape (sub-project #3).
- Unassigned-task archival/removal is explicitly out of scope (see Decisions).
- Revoked-token handling is a plain failure for now; a fuller "clear token and return to sign-in" flow is a future improvement, not built here.
- The `.app` bundle question (flagged after sub-project #2, relevant to OAuth) is unaffected by this sub-project — sync uses the already-built `KantataAPIClient`/`TokenStore`, nothing bundle-dependent.
