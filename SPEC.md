# Kantata time tracker — desktop app spec

Native macOS desktop app for logging time and updating task status against Kantata OX (formerly Mavenlink). Prototyped as a set of UI mockups in Claude chat; this document captures the resulting design and behavior decisions for implementation.

## Platform

- Native macOS desktop app (not mobile, not web).
- Authenticates via Kantata's OAuth 2.0 authorization-code flow against `https://api.mavenlink.com/api/v1/` (see Auth section).

## Screen: today view

Single-day view only — no week grid. Day is navigated one at a time via arrows in the toolbar; there is no need to ever render the full week.

### Toolbar
- macOS traffic-light window chrome (left).
- Day navigation, centered: `<` Today's date `>`. Arrows shift one day at a time.
- Sync button, top right (see Sync section).
- Small "Last synced X ago" caption directly under the toolbar, right-aligned.

### Running timer banner
- Sits pinned directly below the toolbar, **always visible regardless of which day is being viewed** (the timer is tied to "now," not to the day currently on screen).
- Shows: project name, task name, live elapsed time (HH:MM:SS), stop button.
- Accent-colored strip to distinguish it from the rest of the UI.

### Task list
- Grouped by project. Each project group has a header row: colored dot, project name (link — see Links), subtotal ("Xh Ym logged of Yh scheduled").
- Task rows, indented under their project header, columns:
  - **Priority** — small colored dot before the task name. Four tiers: Critical (red), High (coral/orange), Normal (mid-gray), Low (light gray), no dot if no priority set.
  - **Task name** — link (see Links).
  - **Due** — short relative/short date format ("Today", "Fri", "Mon", "Next wk"); "No due date" (muted) if unset.
  - **Scheduled** — duration, or "No time scheduled" (muted italic) if the task is assigned but has no allocation for the day.
  - **Logged** — duration actually logged so far.
  - **Status** — dropdown of the task's actual per-workspace status set (see Status section), or "No status" (muted) if the task has no status assigned.
  - **Quick add** — a "+" icon button (see Time entry).

### Sort order
Within a project group, tasks sort by:
1. Priority: Critical → High → Normal → Low → (none, last)
2. Then due date, ascending (no due date sorts last within its priority tier)

### Mixed scheduled / unscheduled tasks
- Tasks assigned to the user but with no time allocated for the day appear in the **same list**, mixed in with scheduled tasks (not a separate section, not hidden).
- Data comes from two different Kantata resources: allocated tasks come from **Daily Scheduled Hours (Story Allocation Days)**; assigned-but-unscheduled tasks come from **Assignments**.
- Logging time against an unscheduled task **creates a time entry without ever creating an allocation** — it does not get pulled into "scheduled."

## Time entry

### Quick add (per row)
Clicking "+" on a task row expands an inline "Log time" field beneath it:
- Text input (placeholder like `1h30m`), duration parser (see below) live-previews the parsed minutes next to the field (e.g. "= 90 min").
- "Log" button confirms and posts; the "+" toggles to "×" to collapse without logging.

### Add time to a new task (bottom of the list)
A fixed row below the list:
1. Project dropdown ("Choose a project") — top-level selection, since a task belongs to exactly one project in Kantata.
2. Task search, scoped to whatever project is selected (no cross-project search — not possible in Kantata's data model).
3. Duration field (same parser as quick add).
4. "Add" button.

### Duration parser (`XhYm` entry → minutes integer)
Format-agnostic on input; always resolves to and posts a plain integer number of minutes.

Accepted forms, in priority order:
1. `2h45m`, `2h 45m` (whitespace before the unit is optional) → hours + minutes
2. `2h` → hours only
3. `45m` → minutes only
4. `2:45` (h:mm) → minutes portion must be 0–59
5. Bare number, int or float, **no unit** → treated as **hours**, converted to minutes and rounded to the nearest whole minute (`1` → 60, `0.75` → 45, `1.5` → 90)

Rules:
- Any `h`/`m` unit present anywhere in the string takes priority over the bare-number-as-hours interpretation.
- Units are case-insensitive.
- Reject and treat as invalid: empty string, unparseable text, negative numbers, a minutes component ≥ 60 in `Xh Ym` form (e.g. `1h90m`), or any parsed total > 1440 minutes (24h).
- On invalid input (blur or submit): show an inline error ("Enter a duration like 1h30m" / "Duration can't exceed 24h"), disable the Log/Add button, and **revert the field to its last valid value** if one existed for that entry — otherwise clear it to empty.

## Status

- The dropdown only renders if the task actually has a status assigned in Kantata; otherwise show muted "No status" text, no control.
- Options are **pulled live from the task's actual per-workspace status set** (Kantata's Task Statuses / Task Status Sets resources) — not a hardcoded universal list, since status sets are customizable per workspace.
- Changing the status has **no side effects** locally (does not start/stop the timer). It's staged as a field change and pushed to the API on the next sync, same as logged time.

## Project/task links

- Both the project name (group header) and each task name render as accent-colored hyperlinks with a small external-link glyph.
- Clicking either opens the corresponding Kantata web app record **in the user's default browser** — not in-app.
- Only applies to tasks/projects that already exist in Kantata with a known ID (all tasks in this app are pre-existing/assigned, never created from scratch here).
- URL pattern used in mockups (needs to be verified against Kantata's actual web app routes before implementation): `https://app.mavenlink.com/workspaces/{project_id}` for a project, `https://app.mavenlink.com/workspaces/{project_id}/stories/{story_id}` for a task.

## Sync

- **Manual only** — no automatic/interval sync.
- Sync button (refresh icon) lives in the toolbar; "Last synced X ago" caption sits below it.
- **Push:** logged time entries, status changes.
- **Pull:** newly-assigned tasks, updated schedules/allocations (both Assignments and Daily Scheduled Hours).

### During sync
- The entire screen dims and every control disables (day nav, sync button, status dropdowns, quick-add, etc.) until the sync resolves.
- A centered spinner + "Syncing with Kantata…" label overlays the dimmed screen.

### On failure
- Red, non-blocking toast/banner naming the actual reason (e.g. "Couldn't reach Kantata. Check your connection and try again.").
- Inline "Retry" button plus a dismiss control.

### Staleness
- If more than **10 hours** have passed since the last successful sync, show a persistent amber banner: "X hours since last sync. Your schedule may be out of date." with its own "Sync now" shortcut.
- Non-blocking — coexists with normal use of the app.

### Conflict resolution
- Triggers when a field (status, scheduled time, logged time, etc.) has changed **both locally and on the server** since the last successful sync.
- Blocking modal, screen still locked behind it (same dimmed treatment as the syncing state).
- **Per-field granularity** — a task with two conflicting fields (e.g. status and time) shows two separate resolution rows, each independently resolvable.
- **No default selection.** Each conflict must be explicitly resolved: "Keep mine" (local value) vs. "Use Kantata's" (server value). Any unresolved field shows a "Choose one" hint.
- "Apply and continue sync" stays **disabled** until every listed conflict has an explicit choice.
- "Cancel sync" aborts the **entire** sync attempt — nothing gets pushed or pulled, including non-conflicting items that would otherwise have synced cleanly.

## Auth (first launch)

- Kantata uses standard OAuth 2.0, authorization-code grant (`https://app.mavenlink.com/oauth/authorize` → `https://app.mavenlink.com/oauth/token`).
- First-launch screen (only content in the window, no toolbar/list yet): centered icon, "Connect your Kantata account" heading, one-line description of what access is for ("Sign in to pull your scheduled tasks and push logged time and statuses back to Kantata."), single primary button "Sign in with Kantata."
- Clicking the button opens the **system default browser** to Kantata's `/oauth/authorize`; the app needs a redirect handler (custom URI scheme or loopback listener) to receive the returned auth code, per a native desktop OAuth flow.
- Fine print under the button: "Opens your browser to sign in securely. You'll be redirected back here once you approve access."
- **Not yet designed** (flagged as open items, see below): the waiting/pending state while the browser tab is open, a denial state, and an expired/invalid-code error state.

## Open items / not yet resolved in this prototyping pass

- Real Kantata task status values and their per-workspace status set — confirm actual data, don't assume a fixed tier list.
- Whether status changes are held locally and pushed only at the next manual sync, or pushed immediately — current design assumes **staged until sync** (consistent with how logged time already works), but this wasn't explicitly confirmed.
- OAuth pending/waiting state, user-denies-access state, and expired/revoked-token handling (Kantata tokens don't expire per their docs, but can be revoked by the user, which errors on next use).
- Verify actual Kantata web app URL patterns for project/task deep links before hardcoding the pattern above.
- Secure storage of the OAuth token on macOS (e.g. Keychain) — not discussed, but required given Kantata's own security guidance that tokens must be treated like passwords.

## Relevant Kantata API resources (from developer.kantata.com)

- **Auth:** OAuth 2.0 — `/oauth/authorize`, `/oauth/token`. Base API: `https://api.mavenlink.com/api/v1/`.
- **Scheduling:** Workweeks, Workweek Memberships, Holiday Calendars, Holiday Calendar Associations/Memberships, Holidays, Time Off Entries.
- **Tasks:** Assignments, Daily Scheduled Hours (Story Allocation Days), Stories, Story Dependencies, Story State Changes, Story Tasks, Followers.
- **Time Tracking:** Time Entries, Timesheet Approvals, Timesheet Cancellations, Timesheet Rejections, Timesheet Submissions, Line Item Locks.
- **Account Settings & Members:** Task Status Sets, Task Statuses, Users.
