# Secret Management & Release Pipeline

## Problem

`TraxApp.swift` currently hardcodes the real Kantata OAuth `client_secret` as a
string literal. The repo (`jackrabbit-design/jrd-trax`) will remain public
(it's how binaries get shared with the team), so this secret cannot live in
git history. There is also currently no way to produce a distributable build
for teammates other than manually archiving in Xcode by hand.

This covers two related pieces:
1. Get the secret out of source and into a per-developer, gitignored file.
2. Add a manual GitHub Actions pipeline that builds an ad-hoc-signed `.app`,
   injecting the secret from a GitHub repository secret, and publishes it as
   a GitHub Release.

## Secret handling

Add `TraxApp/Sources/TraxApp/Secrets.swift`, gitignored:

```swift
enum Secrets {
    static let kantataClientSecret = "..."
}
```

Add a committed template alongside it, `TraxApp/Sources/TraxApp/Secrets.swift.example`:

```swift
enum Secrets {
    static let kantataClientSecret = "REPLACE_WITH_REAL_CLIENT_SECRET"
}
```

`TraxApp.swift`'s `OAuthConfig(...)` call changes from a hardcoded
`clientSecret:` literal to `clientSecret: Secrets.kantataClientSecret`.

`.gitignore` gains an entry for `TraxApp/Sources/TraxApp/Secrets.swift` (the
`.example` file stays tracked).

This file is consumed identically whether building via `swift build`/`swift
test` (bare SwiftPM) or via `Trax.xcodeproj` (both depend on the same
`TraxApp` library target), so no per-build-system special-casing is needed.

Each developer (and CI) creates their own `Secrets.swift` locally/at build
time; it never enters git history. The `clientID` remains a plain literal in
`TraxApp.swift` — it is not confidential (PKCE-public value), so it doesn't
need this treatment.

## CI / release pipeline

### Scheme fix (prerequisite)

`Trax.xcodeproj` currently has no committed *shared* scheme — only
per-developer `xcuserdata`. A clean CI checkout has nothing to build against
with `xcodebuild -scheme Trax`. Fix: add an explicit `schemes:` block to
`project.yml` defining a shared "Trax" scheme (build + archive actions for
the `Trax` target, Release configuration for archive). CI will run
`xcodegen generate` before building, so the `.xcodeproj` (including its
scheme) is regenerated deterministically from `project.yml` rather than
relying on whatever happens to be committed. This doesn't change your local
workflow — `xcodegen generate` is idempotent and safe to re-run locally too.

### Workflow: `.github/workflows/release.yml`

- **Trigger:** `workflow_dispatch` only (manual "Run workflow" button in the
  GitHub UI). No automatic builds on push.
- **Runner:** `macos-latest`.
- **Secret:** a new GitHub Actions repository secret, `KANTATA_CLIENT_SECRET`
  (you'll add this once in GitHub repo settings → Secrets and variables →
  Actions).
- **Steps:**
  1. Checkout the repo.
  2. Select Xcode via `DEVELOPER_DIR` (matches the toolchain quirk already
     documented for local dev — plain CLT breaks the SwiftData macro
     plugin).
  3. Write `TraxApp/Sources/TraxApp/Secrets.swift` from
     `${{ secrets.KANTATA_CLIENT_SECRET }}`.
  4. Install XcodeGen (`brew install xcodegen`) and run `xcodegen generate`.
  5. `xcodebuild archive` (Release configuration, ad-hoc/no code signing —
     `CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`,
     `CODE_SIGNING_ALLOWED=NO`) producing `Trax.xcarchive`.
  6. Extract the built `Trax.app` from the archive's `Products/Applications`
     directory directly (skipping `-exportArchive`, which expects a real
     export/signing method — not needed for an unsigned local build).
  7. Zip `Trax.app` into `Trax.zip`.
  8. Create a GitHub Release (tag `build-<run number>`, or an optional
     `workflow_dispatch` text input for a custom version/tag) and upload
     `Trax.zip` as a release asset. Release notes include a one-line note
     about the Gatekeeper "unidentified developer" warning and the
     right-click-Open workaround.
- **Test run:** the workflow does not run the test suite as a gate — this is
  a release/distribution pipeline, not a CI-on-every-push check. (Out of
  scope: a separate PR-check workflow could be added later if wanted, but
  wasn't requested.)

## Files touched

- `TraxApp/Sources/TraxApp/TraxApp.swift` — reference `Secrets.kantataClientSecret`
- `TraxApp/Sources/TraxApp/Secrets.swift.example` — new, committed template
- `.gitignore` — ignore the real `Secrets.swift`
- `project.yml` — add shared `schemes:` block
- `.github/workflows/release.yml` — new workflow

## Testing

- Existing `swift test` suite is unaffected (no test currently constructs
  `OAuthConfig` via `Secrets`; test files already pass explicit literals).
- Manual verification: run `xcodegen generate` locally after the `project.yml`
  change and confirm `xcodebuild -project Trax.xcodeproj -list` now lists a
  `Trax` scheme.
- The GitHub Actions workflow itself is verified by triggering it manually
  once, after merge, and confirming a Release is published with a working
  `Trax.zip` (this is a manual post-merge check, not an automated test).

## Out of scope

- Developer ID signing / notarization (explicitly deferred; ad-hoc for now).
- Automatic builds on push/PR.
- A separate CI workflow that runs `swift test` as a merge gate.
