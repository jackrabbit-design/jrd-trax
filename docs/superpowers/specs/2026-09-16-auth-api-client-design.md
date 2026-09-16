# Auth + Kantata API client — design spec

Sub-project 3 of 4 for Trax (native macOS Kantata time tracker; see top-level `SPEC.md` for the full product spec). This covers OAuth sign-in, secure token storage, and a typed, tested client for the Kantata REST API. It does **not** wire real Kantata data into the Today view — that reconciliation (pull/push, conflict resolution) is sub-project #4.

## Goals

- Implement the OAuth 2.0 authorization-code flow described in `SPEC.md` § Auth, including the three states it explicitly left undesigned: pending/waiting, denial, and expired/invalid-code error.
- Store the resulting token in the macOS Keychain.
- Build a typed, protocol-based Kantata API client covering the resources this app needs, fully testable offline (no real network calls in the test suite, no real Keychain access in the test suite).
- Gate the app's root view on auth state: signed out → first-launch screen; signed in → today's `TodayView` (still on sample data — see Non-goals).

## Non-goals

- No real Kantata data flows into `TodayView`. Pulling assignments/schedules and pushing time entries/statuses is sub-project #4's job. This sub-project proves the client can fetch and decode real Kantata responses into typed Swift values; reconciling those values with the local SwiftData store is out of scope here.
- No token refresh flow. Per `SPEC.md`, Kantata tokens don't expire (they can be revoked, which surfaces as an auth error on next use, handled generically — not a distinct "refresh" flow).
- No `.app` bundle work. The loopback-listener redirect mechanism (see below) was chosen specifically so this sub-project doesn't need to solve the bundle problem flagged after sub-project #2.

## Blocking external dependency

Real end-to-end testing requires a Kantata OAuth client registered with Kantata (client ID, and a confirmed redirect URI). That registration is pending (the user's Kantata admin needs to add the app) as of this design. Everything here is built and tested against placeholder config and mocked transports; swapping in real values later should require touching only `OAuthConfig`.

**Placeholder values used until real registration exists:**
- Redirect URI: `http://127.0.0.1:51818/callback` — a fixed port, not a random ephemeral one, since it's unconfirmed whether Kantata's authorization server accepts flexible loopback ports per RFC 8252's recommendation. Easy to change once confirmed.
- Client ID: placeholder string constant, swapped for the real one once registration completes.

## Assumptions flagged as open items (unconfirmed against Kantata's real docs)

- **PKCE support and no client secret:** this design treats Trax as an OAuth "public client" using PKCE (code verifier/challenge) instead of a client secret — the standard, recommended approach for native/desktop apps, and it avoids embedding a secret in the binary. Whether Kantata's authorization server actually validates PKCE, or requires a client secret regardless, is unconfirmed. If a secret turns out to be required, `OAuthConfig` gets one more field.
- **Redirect URI port flexibility:** see above.
- **Kantata API response envelope/shape:** Kantata/Mavenlink's API has historically used a JSON:API-like envelope (a `results` array of IDs plus keyed collections). The DTOs below are written against that expected shape but are unverified until real responses can be captured. Flagged the same way `SPEC.md` already flags the unverified deep-link URL pattern.

## Package structure

New local Swift package `KantataAPI` (sibling to `TraxKit` and the root `TraxApp` package), added as a local path dependency of `TraxApp`. Kept separate from `TraxKit` so the domain/persistence layer stays free of networking/URLSession/Keychain concerns; separate from `TraxApp` so it's testable without SwiftUI.

```
KantataAPI/
  Package.swift
  Sources/KantataAPI/
    OAuth/
      PKCE.swift
      OAuthConfig.swift
      OAuthToken.swift
      OAuthError.swift
      OAuthClient.swift        (protocol)
      LoopbackListener.swift
      LoopbackOAuthClient.swift (real implementation)
    TokenStorage/
      TokenStore.swift         (protocol)
      SecItemStore.swift       (protocol wrapping raw Keychain calls, for testability)
      KeychainTokenStore.swift (real implementation, using SecItemStore)
    HTTP/
      HTTPTransport.swift      (protocol)
      URLSessionHTTPTransport.swift
    Client/
      KantataAPIClient.swift
      Models/                  (DTOs: Workspace, TaskStatus, StatusSet, Assignment, DailyScheduledHour, Story, TimeEntry, User)
  Tests/KantataAPITests/
    PKCETests.swift
    LoopbackOAuthClientTests.swift  (fake transport + fake listener)
    KeychainTokenStoreTests.swift   (fake SecItemStore, never touches the real Keychain)
    KantataAPIClientTests.swift     (stub HTTPTransport returning canned JSON fixtures)
```

## OAuth flow

- Authorization-code grant against `https://app.mavenlink.com/oauth/authorize` → `https://app.mavenlink.com/oauth/token`, base API `https://api.mavenlink.com/api/v1/`.
- PKCE code verifier/challenge generated per attempt (see Assumptions).
- Redirect via a loopback HTTP listener: the app starts a tiny local HTTP server on the fixed port before opening the browser (`NSWorkspace.shared.open` to the authorize URL), waits for the redirect carrying `code` (or `error`), serves a simple "you can close this window" HTML response, then shuts the listener down.
- `OAuthClient` is a protocol (`func signIn() async throws -> OAuthToken`, `func cancel()`), so the UI flow and its tests never depend on a real browser or real sockets — tests inject a fake that resolves/throws immediately.

### First-launch UI states (the three `SPEC.md` left undesigned)

An `@Observable AuthFlowController` (in `TraxApp`, orchestrating `KantataAPI`'s `OAuthClient` + `TokenStore`) drives a state enum:

- **`notStarted`** — the screen `SPEC.md` already specifies: icon, "Connect your Kantata account," description, "Sign in with Kantata" button, fine print.
- **`waiting`** — shown immediately after the button is tapped, while the browser is open and the loopback listener is running: a spinner, "Waiting for you to sign in…", and a "Cancel" button that stops the listener and returns to `notStarted`.
- **`denied`** — the loopback redirect carries `error=access_denied` (or similar): a message explaining access was declined and why it's needed, with a "Try again" button back to `notStarted`.
- **`failed(message)`** — code-exchange failure (network error, invalid/expired code, unexpected response): a generic "Something went wrong signing in" message plus the underlying reason where safe to show, and "Try again."

On success, the token is written to `TokenStore`, and `AuthGateView` (new, wraps `TraxApp`'s `WindowGroup` content) switches from `FirstLaunchView` to the existing `TodayView`.

## Token storage

- `TokenStore` protocol: `save(_:) throws`, `load() throws -> OAuthToken?`, `delete() throws`.
- `KeychainTokenStore` implements it using `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete`, but only through a thin `SecItemStore` protocol wrapping those calls — so `KeychainTokenStoreTests` can inject a fake and never touch the real Keychain (avoids permission prompts and flakiness when tests run unattended).

## API client

- `HTTPTransport` protocol: `func send(_ request: URLRequest) async throws -> (Data, URLResponse)`. `URLSessionHTTPTransport` is the real implementation; tests use a stub returning canned JSON per request.
- `KantataAPIClient` exposes typed async methods for exactly the resources this app needs (per `SPEC.md` § Relevant Kantata API resources):
  - Task Statuses / Task Status Sets
  - Assignments
  - Daily Scheduled Hours (Story Allocation Days)
  - Stories (tasks)
  - Time Entries (create)
  - enough of Users/Workspaces to resolve "me" and project name/color
- DTOs are `Codable` structs decoded from the client's responses — see the open item above about the unverified envelope shape.

## App-side integration

- `AuthGateView.swift` (new) — becomes the content of `TraxApp`'s `WindowGroup`, replacing the direct `TodayView()` reference. On appear, checks `TokenStore.load()`; if a token exists, shows `TodayView()`; otherwise shows `FirstLaunchView()` driven by `AuthFlowController`.
- `FirstLaunchView.swift` (new) — renders the four states above.
- `TodayView` itself is unchanged — still backed by `SampleData` regardless of auth state, per the Non-goals section.

## Testing plan

- `PKCETests`: verifier/challenge generation produces the expected format (length, character set, S256 challenge derivation).
- `LoopbackOAuthClientTests`: drive the state machine via a fake `OAuthClient`-adjacent transport/listener — success, denial, and failure paths, without any real network or socket activity.
- `KeychainTokenStoreTests`: save/load/delete round-trip against a fake `SecItemStore`.
- `KantataAPIClientTests`: each resource method against a stub `HTTPTransport` returning fixture JSON, plus a malformed-response case per method to confirm decode errors surface as typed errors, not crashes.
- `AuthFlowController`/`FirstLaunchView` state transitions: testable at the controller level (pure state machine) without needing to render SwiftUI.

## Open items / carried forward

- Real Kantata client ID and confirmed redirect URI — pending registration.
- PKCE support and redirect-port flexibility — unconfirmed against Kantata's actual OAuth implementation.
- Kantata API response envelope/shape for each resource — unconfirmed until real responses can be captured; DTOs will likely need adjustment.
- Token revocation handling (Kantata tokens don't expire but can be revoked) — this sub-project's `KantataAPIClient` should surface a distinguishable "unauthorized" error type so a future sub-project can prompt re-authentication, but re-auth *flow* itself (beyond throwing the error) is not built here.
