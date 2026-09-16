# Auth + Kantata API Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement OAuth sign-in (loopback redirect, PKCE, Keychain token storage) and a typed, offline-testable Kantata API client, and gate the app's root view on auth state.

**Architecture:** A new local Swift package `KantataAPI` (sibling to `TraxKit`), added as a dependency of the root `TraxApp` package. Every piece that talks to the outside world (browser, sockets, Keychain, HTTP) sits behind a protocol so it's testable with fakes — no real network calls, no real Keychain access, and no real browser/socket activity in the automated test suite (the one exception, `LoopbackListenerTests`, uses only real local loopback sockets, which is still fully offline). `TraxApp` gets a new `AuthGateView` that shows `FirstLaunchView` (four states: not started, waiting, denied, failed) until a token exists, then shows the existing `TodayView` unchanged.

**Tech Stack:** Swift 6 toolchain, macOS 14+ deployment target, `Network.framework` (loopback listener), `CryptoKit` (PKCE), `Security` framework (Keychain), `URLSession`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-16-auth-api-client-design.md` (and top-level `SPEC.md` § Auth, § Relevant Kantata API resources for the behavior this implements)

## Global Constraints

- macOS 14+ deployment target, matching `TraxKit`/`TraxApp`.
- Swift Testing, not XCTest, for all tests.
- This app is an OAuth **public client** using PKCE — no client secret is stored or transmitted anywhere in this plan.
- Placeholder OAuth config until real Kantata registration exists: redirect URI `http://127.0.0.1:51818/callback` (fixed port, not ephemeral), client ID a placeholder string literal in `TraxApp.swift`. Swapping in real values later should only require editing that one call site.
- **Known unverified assumptions, flagged inline where relevant, not to be "fixed" by guessing during implementation:** whether Kantata's OAuth server validates PKCE or requires a client secret; whether it accepts flexible loopback ports; the exact JSON shape of each API resource. DTOs in this plan use the simplest plausible shape (a flat JSON array of flat objects for list endpoints) — this is a deliberate placeholder, not a researched fact.
- This plan does **not** wire real Kantata data into `TodayView` — it stays on `SampleData` regardless of auth state. Pulling/pushing/reconciling real data is a future sub-project.
- No token refresh flow (Kantata tokens don't expire per `SPEC.md`, only get revoked — surfaced generically as `KantataAPIError.unauthorized`, not a distinct refresh flow).

---

### Task 1: `KantataAPI` package scaffold + PKCE (TDD)

**Files:**
- Create: `KantataAPI/Package.swift`
- Create: `KantataAPI/Sources/KantataAPI/OAuth/PKCE.swift`
- Test: `KantataAPI/Tests/KantataAPITests/PKCETests.swift`

**Interfaces:**
- Produces: `public struct PKCE { let codeVerifier: String; let codeChallenge: String; let codeChallengeMethod: String }`, `public init()` — consumed by Task 5 (`LoopbackOAuthClient`) and Task 2 (`OAuthConfig.makeAuthorizationURL`).

- [ ] **Step 1: Create the package manifest**

`KantataAPI/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KantataAPI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KantataAPI", targets: ["KantataAPI"]),
    ],
    targets: [
        .target(name: "KantataAPI"),
        .testTarget(name: "KantataAPITests", dependencies: ["KantataAPI"]),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`KantataAPI/Tests/KantataAPITests/PKCETests.swift`:
```swift
import Testing
@testable import KantataAPI

@Suite("PKCE")
struct PKCETests {
    @Test("code verifier is 43-128 chars from the unreserved character set")
    func verifierFormat() {
        let pkce = PKCE()
        #expect(pkce.codeVerifier.count >= 43 && pkce.codeVerifier.count <= 128)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.codeVerifier.allSatisfy { allowed.contains($0) })
    }

    @Test("code challenge is base64url with no padding")
    func challengeFormat() {
        let pkce = PKCE()
        #expect(!pkce.codeChallenge.contains("+"))
        #expect(!pkce.codeChallenge.contains("/"))
        #expect(!pkce.codeChallenge.contains("="))
    }

    @Test("challenge method is S256")
    func challengeMethod() {
        #expect(PKCE().codeChallengeMethod == "S256")
    }

    @Test("two instances produce different verifiers")
    func randomness() {
        #expect(PKCE().codeVerifier != PKCE().codeVerifier)
    }

    @Test("matches the known RFC 7636 Appendix B test vector")
    func rfc7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        #expect(PKCE.challenge(forVerifier: verifier) == expectedChallenge)
    }
}
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — `PKCE` doesn't exist yet.

- [ ] **Step 4: Implement PKCE**

`KantataAPI/Sources/KantataAPI/OAuth/PKCE.swift`:
```swift
import Foundation
import CryptoKit

public struct PKCE: Sendable, Equatable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String = "S256"

    public init() {
        self.codeVerifier = Self.makeCodeVerifier()
        self.codeChallenge = Self.challenge(forVerifier: codeVerifier)
    }

    static func makeCodeVerifier(length: Int = 64) -> String {
        let allowed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in allowed.randomElement()! })
    }

    static func challenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `cd KantataAPI && swift test`
Expected: All `PKCETests` PASS, including the RFC 7636 known-vector test.

- [ ] **Step 6: Commit**

```bash
git add KantataAPI/Package.swift KantataAPI/Sources/KantataAPI/OAuth/PKCE.swift KantataAPI/Tests/KantataAPITests/PKCETests.swift
git commit -m "$(cat <<'EOF'
Scaffold KantataAPI package with PKCE

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: OAuth types, HTTP transport (TDD for `OAuthConfig`)

**Files:**
- Create: `KantataAPI/Sources/KantataAPI/OAuth/OAuthToken.swift`
- Create: `KantataAPI/Sources/KantataAPI/OAuth/OAuthError.swift`
- Create: `KantataAPI/Sources/KantataAPI/OAuth/OAuthConfig.swift`
- Create: `KantataAPI/Sources/KantataAPI/HTTP/HTTPTransport.swift`
- Create: `KantataAPI/Sources/KantataAPI/HTTP/URLSessionHTTPTransport.swift`
- Test: `KantataAPI/Tests/KantataAPITests/OAuthConfigTests.swift`

**Interfaces:**
- Produces: `public struct OAuthToken: Codable, Sendable, Equatable { accessToken, tokenType, scope: String?, refreshToken: String?, createdAt: Date }`, `struct OAuthTokenResponse: Decodable` (API wire format, not `public` — internal to the package, used by Task 5), `public enum OAuthError: Error, Equatable, Sendable { cancelled, accessDenied, missingAuthorizationCode, stateMismatch, listenerFailed(String), exchangeFailed(String), unauthorized }`, `public struct OAuthConfig { clientID, redirectPort, authorizeURL, tokenURL, scope, var redirectURI: URL, func makeAuthorizationURL(pkce:state:) -> URL }`, `public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, URLResponse) }`, `public struct URLSessionHTTPTransport: HTTPTransport`.
- Consumes: nothing from Task 1 directly in this task's production code (`OAuthConfig.makeAuthorizationURL` takes a `PKCE` parameter, consumed at the call site in Task 5).

- [ ] **Step 1: Write the failing test**

`KantataAPI/Tests/KantataAPITests/OAuthConfigTests.swift`:
```swift
import Testing
import Foundation
@testable import KantataAPI

@Suite("OAuth config")
struct OAuthConfigTests {
    @Test("redirect URI uses the configured fixed loopback port")
    func redirectURI() {
        let config = OAuthConfig(clientID: "abc", redirectPort: 51818)
        #expect(config.redirectURI.absoluteString == "http://127.0.0.1:51818/callback")
    }

    @Test("authorization URL includes all required query parameters")
    func authorizationURLQueryItems() {
        let config = OAuthConfig(clientID: "my-client-id", redirectPort: 51818, scope: "read write")
        let pkce = PKCE()
        let url = config.makeAuthorizationURL(pkce: pkce, state: "test-state")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(items["client_id"] == "my-client-id")
        #expect(items["redirect_uri"] == "http://127.0.0.1:51818/callback")
        #expect(items["response_type"] == "code")
        #expect(items["state"] == "test-state")
        #expect(items["code_challenge"] == pkce.codeChallenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["scope"] == "read write")
    }

    @Test("scope is omitted from the URL when nil")
    func noScopeWhenNil() {
        let config = OAuthConfig(clientID: "abc", redirectPort: 51818, scope: nil)
        let url = config.makeAuthorizationURL(pkce: PKCE(), state: "s")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(!(components.queryItems ?? []).contains { $0.name == "scope" })
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — `OAuthConfig` doesn't exist yet.

- [ ] **Step 3: Create `OAuthToken`**

`KantataAPI/Sources/KantataAPI/OAuth/OAuthToken.swift`:
```swift
import Foundation

/// The app-level, persisted representation of a token — includes
/// `createdAt`, set locally when the token is received, not decoded
/// from the API response.
public struct OAuthToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let tokenType: String
    public let scope: String?
    public let refreshToken: String?
    public let createdAt: Date

    public init(accessToken: String, tokenType: String, scope: String?, refreshToken: String?, createdAt: Date = .now) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
        self.refreshToken = refreshToken
        self.createdAt = createdAt
    }
}

/// The raw token-endpoint response shape, decoded from the wire before
/// being wrapped into an `OAuthToken` with a local `createdAt`.
struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case refreshToken = "refresh_token"
    }
}
```

- [ ] **Step 4: Create `OAuthError`**

`KantataAPI/Sources/KantataAPI/OAuth/OAuthError.swift`:
```swift
public enum OAuthError: Error, Equatable, Sendable {
    case cancelled
    case accessDenied
    case missingAuthorizationCode
    case stateMismatch
    case listenerFailed(String)
    case exchangeFailed(String)
    case unauthorized
}
```

- [ ] **Step 5: Create `OAuthConfig`**

`KantataAPI/Sources/KantataAPI/OAuth/OAuthConfig.swift`:
```swift
import Foundation

public struct OAuthConfig: Sendable {
    public let clientID: String
    public let redirectPort: UInt16
    public let authorizeURL: URL
    public let tokenURL: URL
    public let scope: String?

    public init(
        clientID: String,
        redirectPort: UInt16 = 51818,
        authorizeURL: URL = URL(string: "https://app.mavenlink.com/oauth/authorize")!,
        tokenURL: URL = URL(string: "https://app.mavenlink.com/oauth/token")!,
        scope: String? = nil
    ) {
        self.clientID = clientID
        self.redirectPort = redirectPort
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.scope = scope
    }

    public var redirectURI: URL {
        URL(string: "http://127.0.0.1:\(redirectPort)/callback")!
    }

    public func makeAuthorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod),
        ]
        if let scope {
            items.append(URLQueryItem(name: "scope", value: scope))
        }
        components.queryItems = items
        return components.url!
    }
}
```

- [ ] **Step 6: Create the HTTP transport protocol and real implementation**

`KantataAPI/Sources/KantataAPI/HTTP/HTTPTransport.swift`:
```swift
import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}
```

`KantataAPI/Sources/KantataAPI/HTTP/URLSessionHTTPTransport.swift`:
```swift
import Foundation

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
```

- [ ] **Step 7: Run the test, verify it passes**

Run: `cd KantataAPI && swift test`
Expected: All `OAuthConfigTests` PASS (`PKCETests` from Task 1 still pass too).

- [ ] **Step 8: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/OAuth/OAuthToken.swift KantataAPI/Sources/KantataAPI/OAuth/OAuthError.swift KantataAPI/Sources/KantataAPI/OAuth/OAuthConfig.swift KantataAPI/Sources/KantataAPI/HTTP KantataAPI/Tests/KantataAPITests/OAuthConfigTests.swift
git commit -m "$(cat <<'EOF'
Add OAuth token/error types, OAuthConfig, and HTTP transport

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Token storage — `TokenStore`, `SecItemStore`, `KeychainTokenStore` (TDD via fake)

**Files:**
- Create: `KantataAPI/Sources/KantataAPI/TokenStorage/TokenStore.swift`
- Create: `KantataAPI/Sources/KantataAPI/TokenStorage/SecItemStore.swift`
- Create: `KantataAPI/Sources/KantataAPI/TokenStorage/KeychainTokenStore.swift`
- Test: `KantataAPI/Tests/KantataAPITests/KeychainTokenStoreTests.swift`

**Interfaces:**
- Consumes: `OAuthToken` (Task 2).
- Produces: `public protocol TokenStore: Sendable { func save(_ token: OAuthToken) throws; func load() throws -> OAuthToken?; func delete() throws }`, `public struct KeychainTokenStore: TokenStore` — consumed by Task 8 (`AuthFlowController`) and Task 9 (`TraxApp.swift`).

- [ ] **Step 1: Write the failing tests**

`KantataAPI/Tests/KantataAPITests/KeychainTokenStoreTests.swift`:
```swift
import Testing
import Foundation
import Security
@testable import KantataAPI

final class FakeSecItemStore: SecItemStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func add(_ attributes: [String: Any]) -> OSStatus {
        let account = attributes[kSecAttrAccount as String] as! String
        if storage[account] != nil { return errSecDuplicateItem }
        storage[account] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        let account = query[kSecAttrAccount as String] as! String
        guard storage[account] != nil else { return errSecItemNotFound }
        storage[account] = attributesToUpdate[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        let account = query[kSecAttrAccount as String] as! String
        guard let data = storage[account] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data as AnyObject)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        let account = query[kSecAttrAccount as String] as! String
        guard storage[account] != nil else { return errSecItemNotFound }
        storage.removeValue(forKey: account)
        return errSecSuccess
    }
}

@Suite("Keychain token store")
struct KeychainTokenStoreTests {
    private func makeToken() -> OAuthToken {
        OAuthToken(accessToken: "tok", tokenType: "Bearer", scope: "read", refreshToken: nil, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test("load returns nil when nothing has been saved")
    func loadEmpty() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        #expect(try store.load() == nil)
    }

    @Test("save then load round-trips the token")
    func saveThenLoad() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        let token = makeToken()
        try store.save(token)
        #expect(try store.load() == token)
    }

    @Test("saving twice updates rather than duplicating")
    func saveTwiceUpdates() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        try store.save(makeToken())
        let updated = OAuthToken(accessToken: "tok2", tokenType: "Bearer", scope: nil, refreshToken: nil, createdAt: Date(timeIntervalSince1970: 100))
        try store.save(updated)
        #expect(try store.load() == updated)
    }

    @Test("delete removes the token")
    func deleteRemoves() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        try store.save(makeToken())
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("deleting when nothing exists does not throw")
    func deleteWhenEmpty() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        try store.delete()
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — `SecItemStore`, `KeychainTokenStore` don't exist yet.

- [ ] **Step 3: Create `SecItemStore` (protocol + real Keychain implementation)**

`KantataAPI/Sources/KantataAPI/TokenStorage/SecItemStore.swift`:
```swift
import Foundation
import Security

/// Thin wrapper around the raw Security framework calls, so
/// `KeychainTokenStore` can be tested with a fake that never touches
/// the real Keychain.
public protocol SecItemStore: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?)
    func delete(_ query: [String: Any]) -> OSStatus
}

public struct KeychainSecItemStore: SecItemStore {
    public init() {}

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    }

    public func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Create `TokenStore` and `KeychainTokenStore`**

`KantataAPI/Sources/KantataAPI/TokenStorage/TokenStore.swift`:
```swift
public protocol TokenStore: Sendable {
    func save(_ token: OAuthToken) throws
    func load() throws -> OAuthToken?
    func delete() throws
}

public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
}
```

`KantataAPI/Sources/KantataAPI/TokenStorage/KeychainTokenStore.swift`:
```swift
import Foundation
import Security

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String
    private let secItemStore: any SecItemStore

    public init(
        service: String = "com.jumpingjackrabbit.trax.oauth",
        account: String = "kantata",
        secItemStore: any SecItemStore = KeychainSecItemStore()
    ) {
        self.service = service
        self.account = account
        self.secItemStore = secItemStore
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func save(_ token: OAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = secItemStore.add(addQuery)
        if addStatus == errSecDuplicateItem {
            let updateStatus = secItemStore.update(query: baseQuery, attributesToUpdate: [kSecValueData as String: data])
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
        } else if addStatus != errSecSuccess {
            throw KeychainError.status(addStatus)
        }
    }

    public func load() throws -> OAuthToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = secItemStore.copyMatching(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func delete() throws {
        let status = secItemStore.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `cd KantataAPI && swift test`
Expected: All `KeychainTokenStoreTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/TokenStorage KantataAPI/Tests/KantataAPITests/KeychainTokenStoreTests.swift
git commit -m "$(cat <<'EOF'
Add TokenStore protocol and Keychain-backed implementation

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Loopback listener (TDD via real local sockets)

**Files:**
- Create: `KantataAPI/Sources/KantataAPI/OAuth/CallbackListening.swift`
- Create: `KantataAPI/Sources/KantataAPI/OAuth/LoopbackListener.swift`
- Test: `KantataAPI/Tests/KantataAPITests/LoopbackListenerTests.swift`

**Interfaces:**
- Produces: `public protocol CallbackListening: Sendable { func start() async throws -> UInt16; func waitForCallback() async throws -> [String: String]; func stop() }`, `public final class LoopbackListener: CallbackListening` — consumed by Task 5 (`LoopbackOAuthClient`).

- [ ] **Step 1: Write the failing test**

`KantataAPI/Tests/KantataAPITests/LoopbackListenerTests.swift`:
```swift
import Testing
import Foundation
@testable import KantataAPI

@Suite("Loopback listener")
struct LoopbackListenerTests {
    @Test("captures query parameters from a real local GET request")
    func capturesCallbackParams() async throws {
        let listener = LoopbackListener(port: 0)
        let port = try await listener.start()

        async let paramsTask = listener.waitForCallback()

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/callback?code=abc123&state=xyz")!)
        request.httpMethod = "GET"
        _ = try await URLSession.shared.data(for: request)

        let params = try await paramsTask
        #expect(params["code"] == "abc123")
        #expect(params["state"] == "xyz")

        listener.stop()
    }

    @Test("stop() while waiting throws a cancellation error")
    func stopCancelsWait() async throws {
        let listener = LoopbackListener(port: 0)
        _ = try await listener.start()

        async let waitTask = listener.waitForCallback()
        try await Task.sleep(nanoseconds: 100_000_000)
        listener.stop()

        await #expect(throws: (any Error).self) {
            try await waitTask
        }
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — `LoopbackListener` doesn't exist yet.

- [ ] **Step 3: Create `CallbackListening`**

`KantataAPI/Sources/KantataAPI/OAuth/CallbackListening.swift`:
```swift
public protocol CallbackListening: Sendable {
    /// Starts listening on the configured port (or an OS-assigned
    /// ephemeral port if the configured port is 0) and returns the
    /// actual bound port.
    func start() async throws -> UInt16
    /// Suspends until a request arrives, returning its query parameters.
    func waitForCallback() async throws -> [String: String]
    /// Stops listening. If a call to `waitForCallback()` is in flight,
    /// it throws a cancellation error.
    func stop()
}
```

- [ ] **Step 4: Implement `LoopbackListener`**

`KantataAPI/Sources/KantataAPI/OAuth/LoopbackListener.swift`:
```swift
import Foundation
import Network

public final class LoopbackListener: CallbackListening, @unchecked Sendable {
    private let requestedPort: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private let lock = NSLock()

    public init(port: UInt16) {
        self.requestedPort = port
    }

    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        let nwPort = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? self?.requestedPort ?? 0
                    continuation.resume(returning: port)
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: .main)
        }
    }

    public func waitForCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: CancellationError())
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let request = String(data: data, encoding: .utf8) {
                let params = Self.parseQueryParams(fromRequestLine: request)
                self.respond(on: connection)
                self.lock.lock()
                let cont = self.continuation
                self.continuation = nil
                self.lock.unlock()
                cont?.resume(returning: params)
            } else if let error {
                self.lock.lock()
                let cont = self.continuation
                self.continuation = nil
                self.lock.unlock()
                cont?.resume(throwing: error)
            }
        }
    }

    private func respond(on connection: NWConnection) {
        let body = "<html><body>You can close this window and return to Trax.</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseQueryParams(fromRequestLine request: String) -> [String: String] {
        guard let firstLine = request.split(separator: "\r\n").first else { return [:] }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return [:] }
        let path = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(path)") else { return [:] }
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `cd KantataAPI && swift test`
Expected: All `LoopbackListenerTests` PASS. These use real local loopback sockets (127.0.0.1) — no external network access, but not a "pure" unit test either; that's expected and matches the design doc.

- [ ] **Step 6: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/OAuth/CallbackListening.swift KantataAPI/Sources/KantataAPI/OAuth/LoopbackListener.swift KantataAPI/Tests/KantataAPITests/LoopbackListenerTests.swift
git commit -m "$(cat <<'EOF'
Add loopback HTTP listener for the OAuth redirect

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `OAuthClient` protocol + `LoopbackOAuthClient` (TDD via fakes)

**Files:**
- Create: `KantataAPI/Sources/KantataAPI/OAuth/OAuthClient.swift`
- Create: `KantataAPI/Sources/KantataAPI/OAuth/LoopbackOAuthClient.swift`
- Test: `KantataAPI/Tests/KantataAPITests/LoopbackOAuthClientTests.swift`

**Interfaces:**
- Consumes: `PKCE` (Task 1), `OAuthConfig`, `OAuthToken`, `OAuthTokenResponse`, `OAuthError`, `HTTPTransport` (Task 2), `CallbackListening` (Task 4).
- Produces: `public protocol OAuthClient: Sendable { func signIn() async throws -> OAuthToken; func cancel() }`, `public final class LoopbackOAuthClient: OAuthClient` — consumed by Task 8 (`AuthFlowController`) and Task 9 (`TraxApp.swift`).

- [ ] **Step 1: Write the failing tests**

`KantataAPI/Tests/KantataAPITests/LoopbackOAuthClientTests.swift`:
```swift
import Testing
import Foundation
@testable import KantataAPI

final class FakeCallbackListening: CallbackListening, @unchecked Sendable {
    var resultToReturn: Result<[String: String], Error> = .success([:])
    private(set) var stopCalled = false

    func start() async throws -> UInt16 { 0 }
    func waitForCallback() async throws -> [String: String] { try resultToReturn.get() }
    func stop() { stopCalled = true }
}

final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    var resultToReturn: Result<(Data, URLResponse), Error> = .failure(URLError(.badServerResponse))

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try resultToReturn.get()
    }
}

@Suite("Loopback OAuth client")
struct LoopbackOAuthClientTests {
    private func makeConfig() -> OAuthConfig {
        OAuthConfig(clientID: "client-1", redirectPort: 51818)
    }

    private func makeTokenResponse() -> Data {
        """
        {"access_token": "tok-123", "token_type": "Bearer", "scope": "read", "refresh_token": null}
        """.data(using: .utf8)!
    }

    @Test("successful sign-in returns a decoded token and opens the authorization URL")
    func successfulSignIn() async throws {
        // The client generates its own random `state` per sign-in attempt,
        // so a fake listener can't know it in advance. `openBrowser` is
        // where the client hands over the authorization URL it built —
        // this test reads the `state` back out of that URL and configures
        // the listener to echo it, which is the only way a fake can
        // produce a matching state without duplicating the client's
        // internal random generation.
        let listener = FakeCallbackListening()
        let transport = FakeHTTPTransport()
        transport.resultToReturn = .success((makeTokenResponse(), HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))

        var openedURL: URL?
        let client = LoopbackOAuthClient(
            config: makeConfig(),
            transport: transport,
            makeListener: { listener },
            openBrowser: { url in
                openedURL = url
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "state" }?.value ?? ""
                listener.resultToReturn = .success(["code": "auth-code", "state": state])
            }
        )

        let token = try await client.signIn()
        #expect(token.accessToken == "tok-123")
        #expect(token.tokenType == "Bearer")
        #expect(openedURL != nil)
    }

    @Test("access_denied callback throws OAuthError.accessDenied")
    func accessDenied() async throws {
        let listener = FakeCallbackListening()
        listener.resultToReturn = .success(["error": "access_denied"])
        let client = LoopbackOAuthClient(
            config: makeConfig(),
            transport: FakeHTTPTransport(),
            makeListener: { listener },
            openBrowser: { _ in }
        )

        await #expect(throws: OAuthError.accessDenied) {
            try await client.signIn()
        }
    }

    @Test("mismatched state throws OAuthError.stateMismatch")
    func stateMismatch() async throws {
        let listener = FakeCallbackListening()
        listener.resultToReturn = .success(["code": "auth-code", "state": "wrong-state"])
        let client = LoopbackOAuthClient(
            config: makeConfig(),
            transport: FakeHTTPTransport(),
            makeListener: { listener },
            openBrowser: { _ in }
        )

        await #expect(throws: OAuthError.stateMismatch) {
            try await client.signIn()
        }
    }

    @Test("cancellation from the listener maps to OAuthError.cancelled")
    func cancelledListenerMapsToCancelled() async throws {
        let listener = FakeCallbackListening()
        listener.resultToReturn = .failure(CancellationError())
        let client = LoopbackOAuthClient(
            config: makeConfig(),
            transport: FakeHTTPTransport(),
            makeListener: { listener },
            openBrowser: { _ in }
        )

        await #expect(throws: OAuthError.cancelled) {
            try await client.signIn()
        }
    }

    @Test("transport failure during exchange throws OAuthError.exchangeFailed")
    func exchangeFailure() async throws {
        let echoListener = FakeCallbackListening()
        let transport = FakeHTTPTransport()
        transport.resultToReturn = .failure(URLError(.notConnectedToInternet))
        let client = LoopbackOAuthClient(
            config: makeConfig(),
            transport: transport,
            makeListener: { echoListener },
            openBrowser: { url in
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "state" }?.value ?? ""
                echoListener.resultToReturn = .success(["code": "auth-code", "state": state])
            }
        )

        do {
            _ = try await client.signIn()
            Issue.record("expected exchangeFailed to be thrown")
        } catch let error as OAuthError {
            guard case .exchangeFailed = error else {
                Issue.record("expected .exchangeFailed, got \(error)")
                return
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — `OAuthClient`, `LoopbackOAuthClient` don't exist yet.

- [ ] **Step 3: Create `OAuthClient`**

`KantataAPI/Sources/KantataAPI/OAuth/OAuthClient.swift`:
```swift
public protocol OAuthClient: Sendable {
    func signIn() async throws -> OAuthToken
    func cancel()
}
```

- [ ] **Step 4: Implement `LoopbackOAuthClient`**

`KantataAPI/Sources/KantataAPI/OAuth/LoopbackOAuthClient.swift`:
```swift
import Foundation

public final class LoopbackOAuthClient: OAuthClient, @unchecked Sendable {
    private let config: OAuthConfig
    private let transport: any HTTPTransport
    private let makeListener: @Sendable () -> any CallbackListening
    private let openBrowser: @Sendable (URL) -> Void
    private var activeListener: (any CallbackListening)?
    private let lock = NSLock()

    public init(
        config: OAuthConfig,
        transport: any HTTPTransport,
        makeListener: @escaping @Sendable () -> any CallbackListening,
        openBrowser: @escaping @Sendable (URL) -> Void
    ) {
        self.config = config
        self.transport = transport
        self.makeListener = makeListener
        self.openBrowser = openBrowser
    }

    public func signIn() async throws -> OAuthToken {
        let pkce = PKCE()
        let state = UUID().uuidString
        let listener = makeListener()
        lock.lock(); activeListener = listener; lock.unlock()

        _ = try await listener.start()
        let authURL = config.makeAuthorizationURL(pkce: pkce, state: state)
        openBrowser(authURL)

        let params: [String: String]
        do {
            params = try await listener.waitForCallback()
        } catch is CancellationError {
            lock.lock(); activeListener = nil; lock.unlock()
            throw OAuthError.cancelled
        } catch {
            lock.lock(); activeListener = nil; lock.unlock()
            throw error
        }
        listener.stop()
        lock.lock(); activeListener = nil; lock.unlock()

        if let errorParam = params["error"] {
            throw errorParam == "access_denied" ? OAuthError.accessDenied : OAuthError.exchangeFailed(errorParam)
        }
        guard let code = params["code"] else {
            throw OAuthError.missingAuthorizationCode
        }
        guard let returnedState = params["state"], returnedState == state else {
            throw OAuthError.stateMismatch
        }

        return try await exchange(code: code, pkce: pkce)
    }

    public func cancel() {
        lock.lock()
        let listener = activeListener
        activeListener = nil
        lock.unlock()
        listener?.stop()
    }

    private func exchange(code: String, pkce: PKCE) async throws -> OAuthToken {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: pkce.codeVerifier),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw OAuthError.exchangeFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OAuthError.exchangeFailed("HTTP \(http.statusCode)")
        }
        do {
            let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            return OAuthToken(accessToken: decoded.accessToken, tokenType: decoded.tokenType, scope: decoded.scope, refreshToken: decoded.refreshToken)
        } catch {
            throw OAuthError.exchangeFailed("Could not decode token response")
        }
    }
}
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `cd KantataAPI && swift test`
Expected: All `LoopbackOAuthClientTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/OAuth/OAuthClient.swift KantataAPI/Sources/KantataAPI/OAuth/LoopbackOAuthClient.swift KantataAPI/Tests/KantataAPITests/LoopbackOAuthClientTests.swift
git commit -m "$(cat <<'EOF'
Add OAuthClient protocol and loopback-based implementation

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Kantata resource DTOs (TDD via fixture JSON)

**Files:**
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/WorkspaceDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/TaskStatusDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/StatusSetDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/AssignmentDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/DailyScheduledHourDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/StoryDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/TimeEntryDTO.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/Models/UserDTO.swift`
- Test: `KantataAPI/Tests/KantataAPITests/DTODecodingTests.swift`

**Interfaces:**
- Produces: 8 `Codable`/`Decodable` DTO structs, one per Kantata resource this app needs — consumed by Task 7 (`KantataAPIClient`).

**Note on the response shape assumption:** these DTOs assume the simplest plausible shape — a flat JSON object per resource — per the plan's Global Constraints. This is unverified against Kantata's real API and may need revision once real responses can be captured; that revision is out of scope for this task.

- [ ] **Step 1: Write the failing tests**

`KantataAPI/Tests/KantataAPITests/DTODecodingTests.swift`:
```swift
import Testing
import Foundation
@testable import KantataAPI

@Suite("DTO decoding")
struct DTODecodingTests {
    @Test("WorkspaceDTO decodes")
    func workspace() throws {
        let json = #"{"id": "w1", "title": "Acme Redesign"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(WorkspaceDTO.self, from: json)
        #expect(dto.id == "w1")
        #expect(dto.title == "Acme Redesign")
    }

    @Test("TaskStatusDTO decodes")
    func taskStatus() throws {
        let json = #"{"id": "s1", "name": "In Progress"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TaskStatusDTO.self, from: json)
        #expect(dto.id == "s1")
        #expect(dto.name == "In Progress")
    }

    @Test("StatusSetDTO decodes with nested status ids")
    func statusSet() throws {
        let json = #"{"id": "set1", "name": "Default", "status_ids": ["s1", "s2"]}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StatusSetDTO.self, from: json)
        #expect(dto.id == "set1")
        #expect(dto.statusIds == ["s1", "s2"])
    }

    @Test("AssignmentDTO decodes")
    func assignment() throws {
        let json = #"{"id": "a1", "story_id": "st1", "workspace_id": "w1"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(AssignmentDTO.self, from: json)
        #expect(dto.storyId == "st1")
        #expect(dto.workspaceId == "w1")
    }

    @Test("DailyScheduledHourDTO decodes")
    func dailyScheduledHour() throws {
        let json = #"{"id": "d1", "story_id": "st1", "date": "2026-09-16", "hours": 1.5}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(DailyScheduledHourDTO.self, from: json)
        #expect(dto.date == "2026-09-16")
        #expect(dto.hours == 1.5)
    }

    @Test("StoryDTO decodes with optional fields")
    func story() throws {
        let json = #"{"id": "st1", "workspace_id": "w1", "title": "Design homepage", "priority": "high", "due_date": "2026-09-20", "status_id": "s1"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StoryDTO.self, from: json)
        #expect(dto.title == "Design homepage")
        #expect(dto.priority == "high")
        #expect(dto.dueDate == "2026-09-20")
    }

    @Test("StoryDTO decodes when optional fields are missing")
    func storyMinimal() throws {
        let json = #"{"id": "st2", "workspace_id": "w1", "title": "Untitled"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StoryDTO.self, from: json)
        #expect(dto.priority == nil)
        #expect(dto.dueDate == nil)
        #expect(dto.statusId == nil)
    }

    @Test("TimeEntryDTO decodes")
    func timeEntry() throws {
        let json = #"{"id": "te1", "story_id": "st1", "date": "2026-09-16", "hours": 0.75}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TimeEntryDTO.self, from: json)
        #expect(dto.hours == 0.75)
    }

    @Test("UserDTO decodes")
    func user() throws {
        let json = #"{"id": "u1", "full_name": "Chris K", "email": "ck@jumpingjackrabbit.com"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(UserDTO.self, from: json)
        #expect(dto.fullName == "Chris K")
        #expect(dto.email == "ck@jumpingjackrabbit.com")
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — none of the DTO types exist yet.

- [ ] **Step 3: Create the DTOs**

`KantataAPI/Sources/KantataAPI/Client/Models/WorkspaceDTO.swift`:
```swift
public struct WorkspaceDTO: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/TaskStatusDTO.swift`:
```swift
public struct TaskStatusDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/StatusSetDTO.swift`:
```swift
public struct StatusSetDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let statusIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case statusIds = "status_ids"
    }
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/AssignmentDTO.swift`:
```swift
public struct AssignmentDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    public let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case workspaceId = "workspace_id"
    }
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/DailyScheduledHourDTO.swift`:
```swift
public struct DailyScheduledHourDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    /// Kept as the raw wire string (e.g. "2026-09-16") — date parsing
    /// into a real `Date` happens at the mapping layer, not here.
    public let date: String
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case date, hours
    }
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/StoryDTO.swift`:
```swift
public struct StoryDTO: Codable, Sendable, Equatable {
    public let id: String
    public let workspaceId: String
    public let title: String
    public let priority: String?
    public let dueDate: String?
    public let statusId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case title, priority
        case dueDate = "due_date"
        case statusId = "status_id"
    }
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/TimeEntryDTO.swift`:
```swift
public struct TimeEntryDTO: Codable, Sendable, Equatable {
    public let id: String
    public let storyId: String
    public let date: String
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case id
        case storyId = "story_id"
        case date, hours
    }
}

public struct TimeEntryCreateRequest: Encodable, Sendable, Equatable {
    public let storyId: String
    public let date: String
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case storyId = "story_id"
        case date, hours
    }

    public init(storyId: String, date: String, hours: Double) {
        self.storyId = storyId
        self.date = date
        self.hours = hours
    }
}
```

`KantataAPI/Sources/KantataAPI/Client/Models/UserDTO.swift`:
```swift
public struct UserDTO: Codable, Sendable, Equatable {
    public let id: String
    public let fullName: String
    public let email: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
    }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `cd KantataAPI && swift test`
Expected: All `DTODecodingTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/Client/Models KantataAPI/Tests/KantataAPITests/DTODecodingTests.swift
git commit -m "$(cat <<'EOF'
Add Kantata resource DTOs

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `KantataAPIClient` (TDD via stub transport)

**Files:**
- Create: `KantataAPI/Sources/KantataAPI/Client/KantataAPIError.swift`
- Create: `KantataAPI/Sources/KantataAPI/Client/KantataAPIClient.swift`
- Test: `KantataAPI/Tests/KantataAPITests/KantataAPIClientTests.swift`

**Interfaces:**
- Consumes: `HTTPTransport` (Task 2), the 8 DTOs + `TimeEntryCreateRequest` (Task 6).
- Produces: `public struct KantataAPIClient` with `fetchTaskStatuses()`, `fetchStatusSets()`, `fetchAssignments()`, `fetchDailyScheduledHours()`, `fetchStories()`, `fetchCurrentUser()`, `createTimeEntry(_:)` — consumed by a future sub-project (#4), not by anything in this plan.

- [ ] **Step 1: Write the failing tests**

`KantataAPI/Tests/KantataAPITests/KantataAPIClientTests.swift`:
```swift
import Testing
import Foundation
@testable import KantataAPI

final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
    var responseData: Data = Data()
    var statusCode: Int = 200
    private(set) var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (responseData, response)
    }
}

@Suite("Kantata API client")
struct KantataAPIClientTests {
    @Test("fetchTaskStatuses decodes a list and sets the Authorization header")
    func fetchTaskStatuses() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"[{"id": "s1", "name": "In Progress"}]"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok-123" })

        let statuses = try await client.fetchTaskStatuses()
        #expect(statuses == [TaskStatusDTO(id: "s1", name: "In Progress")])
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
    }

    @Test("fetchCurrentUser decodes a single object")
    func fetchCurrentUser() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"id": "u1", "full_name": "Chris K", "email": "ck@jumpingjackrabbit.com"}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        let user = try await client.fetchCurrentUser()
        #expect(user.fullName == "Chris K")
    }

    @Test("createTimeEntry posts the request body and decodes the response")
    func createTimeEntry() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"id": "te1", "story_id": "st1", "date": "2026-09-16", "hours": 1.5}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        let result = try await client.createTimeEntry(TimeEntryCreateRequest(storyId: "st1", date: "2026-09-16", hours: 1.5))
        #expect(result.hours == 1.5)
        #expect(transport.lastRequest?.httpMethod == "POST")
    }

    @Test("401 response throws unauthorized")
    func unauthorized() async throws {
        let transport = StubHTTPTransport()
        transport.statusCode = 401
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        await #expect(throws: KantataAPIError.unauthorized) {
            try await client.fetchTaskStatuses()
        }
    }

    @Test("malformed JSON throws a decoding error, not a crash")
    func malformedResponse() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"not": "a list"}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        do {
            _ = try await client.fetchTaskStatuses()
            Issue.record("expected a decoding error")
        } catch let error as KantataAPIError {
            guard case .decodingFailed = error else {
                Issue.record("expected .decodingFailed, got \(error)")
                return
            }
        }
    }

    @Test("non-2xx, non-401 response throws httpError with the status code")
    func genericHTTPError() async throws {
        let transport = StubHTTPTransport()
        transport.statusCode = 500
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        await #expect(throws: KantataAPIError.httpError(500)) {
            try await client.fetchTaskStatuses()
        }
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `cd KantataAPI && swift test`
Expected: FAIL to compile — `KantataAPIClient`, `KantataAPIError` don't exist yet.

- [ ] **Step 3: Create `KantataAPIError`**

`KantataAPI/Sources/KantataAPI/Client/KantataAPIError.swift`:
```swift
public enum KantataAPIError: Error, Sendable {
    case unauthorized
    case httpError(Int)
    case decodingFailed(Error)
}

extension KantataAPIError: Equatable {
    public static func == (lhs: KantataAPIError, rhs: KantataAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized):
            return true
        case let (.httpError(a), .httpError(b)):
            return a == b
        case (.decodingFailed, .decodingFailed):
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Implement `KantataAPIClient`**

`KantataAPI/Sources/KantataAPI/Client/KantataAPIClient.swift`:
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

    public func fetchDailyScheduledHours() async throws -> [DailyScheduledHourDTO] {
        try await get("story_allocation_days")
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

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
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

- [ ] **Step 5: Run the tests, verify they pass**

Run: `cd KantataAPI && swift test`
Expected: All `KantataAPIClientTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add KantataAPI/Sources/KantataAPI/Client/KantataAPIError.swift KantataAPI/Sources/KantataAPI/Client/KantataAPIClient.swift KantataAPI/Tests/KantataAPITests/KantataAPIClientTests.swift
git commit -m "$(cat <<'EOF'
Add typed Kantata API client

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `AuthFlowController` (TDD via fakes)

**Files:**
- Create: `TraxApp/Sources/TraxApp/AuthFlowController.swift`
- Test: `TraxApp/Tests/TraxAppTests/AuthFlowControllerTests.swift`
- Modify: `Package.swift` (repo root)

**Interfaces:**
- Consumes: `OAuthClient`, `TokenStore`, `OAuthToken`, `OAuthError` (`KantataAPI`, Tasks 3/5).
- Produces: `enum AuthFlowState: Equatable { notStarted, waiting, signedIn, denied, failed(String) }`, `@MainActor @Observable final class AuthFlowController` with `signIn()`, `cancel()`, `retry()` — consumed by Task 9 (`FirstLaunchView`, `AuthGateView`).

- [ ] **Step 1: Add `KantataAPI` as a dependency of `TraxApp`**

In `Package.swift` (repo root), change:
```swift
    dependencies: [
        .package(path: "TraxKit"),
    ],
    targets: [
        .executableTarget(name: "TraxApp", dependencies: ["TraxKit"], path: "TraxApp/Sources/TraxApp"),
        .testTarget(name: "TraxAppTests", dependencies: ["TraxApp"], path: "TraxApp/Tests/TraxAppTests"),
    ]
```

to:

```swift
    dependencies: [
        .package(path: "TraxKit"),
        .package(path: "KantataAPI"),
    ],
    targets: [
        .executableTarget(name: "TraxApp", dependencies: ["TraxKit", "KantataAPI"], path: "TraxApp/Sources/TraxApp"),
        .testTarget(name: "TraxAppTests", dependencies: ["TraxApp"], path: "TraxApp/Tests/TraxAppTests"),
    ]
```

- [ ] **Step 2: Write the failing tests**

`TraxApp/Tests/TraxAppTests/AuthFlowControllerTests.swift`:
```swift
import Testing
import KantataAPI
@testable import TraxApp

final class FakeOAuthClient: OAuthClient, @unchecked Sendable {
    var resultToReturn: Result<OAuthToken, Error> = .failure(OAuthError.cancelled)
    private(set) var cancelCalled = false

    func signIn() async throws -> OAuthToken { try resultToReturn.get() }
    func cancel() { cancelCalled = true }
}

final class FakeTokenStore: TokenStore, @unchecked Sendable {
    var stored: OAuthToken?

    func save(_ token: OAuthToken) throws { stored = token }
    func load() throws -> OAuthToken? { stored }
    func delete() throws { stored = nil }
}

@Suite("Auth flow controller")
@MainActor
struct AuthFlowControllerTests {
    private func makeToken() -> OAuthToken {
        OAuthToken(accessToken: "tok", tokenType: "Bearer", scope: nil, refreshToken: nil)
    }

    @Test("starts in .signedIn when a token already exists")
    func startsSignedInWithExistingToken() {
        let tokenStore = FakeTokenStore()
        tokenStore.stored = makeToken()
        let controller = AuthFlowController(oauthClient: FakeOAuthClient(), tokenStore: tokenStore)
        #expect(controller.state == .signedIn)
    }

    @Test("starts in .notStarted when no token exists")
    func startsNotStartedWithNoToken() {
        let controller = AuthFlowController(oauthClient: FakeOAuthClient(), tokenStore: FakeTokenStore())
        #expect(controller.state == .notStarted)
    }

    @Test("successful sign-in saves the token and transitions to .signedIn")
    func successfulSignIn() async {
        let oauthClient = FakeOAuthClient()
        oauthClient.resultToReturn = .success(makeToken())
        let tokenStore = FakeTokenStore()
        let controller = AuthFlowController(oauthClient: oauthClient, tokenStore: tokenStore)

        await controller.signIn()

        #expect(controller.state == .signedIn)
        #expect(tokenStore.stored == makeToken())
    }

    @Test("access denied transitions to .denied")
    func accessDenied() async {
        let oauthClient = FakeOAuthClient()
        oauthClient.resultToReturn = .failure(OAuthError.accessDenied)
        let controller = AuthFlowController(oauthClient: oauthClient, tokenStore: FakeTokenStore())

        await controller.signIn()

        #expect(controller.state == .denied)
    }

    @Test("cancellation transitions back to .notStarted")
    func cancellation() async {
        let oauthClient = FakeOAuthClient()
        oauthClient.resultToReturn = .failure(OAuthError.cancelled)
        let controller = AuthFlowController(oauthClient: oauthClient, tokenStore: FakeTokenStore())

        await controller.signIn()

        #expect(controller.state == .notStarted)
    }

    @Test("other errors transition to .failed with a message")
    func otherErrors() async {
        let oauthClient = FakeOAuthClient()
        oauthClient.resultToReturn = .failure(OAuthError.exchangeFailed("network down"))
        let controller = AuthFlowController(oauthClient: oauthClient, tokenStore: FakeTokenStore())

        await controller.signIn()

        guard case .failed = controller.state else {
            Issue.record("expected .failed, got \(controller.state)")
            return
        }
    }

    @Test("cancel() calls the OAuth client's cancel and resets to .notStarted")
    func cancelResets() {
        let oauthClient = FakeOAuthClient()
        let controller = AuthFlowController(oauthClient: oauthClient, tokenStore: FakeTokenStore())

        controller.cancel()

        #expect(oauthClient.cancelCalled)
        #expect(controller.state == .notStarted)
    }

    @Test("retry() resets to .notStarted")
    func retryResets() async {
        let oauthClient = FakeOAuthClient()
        oauthClient.resultToReturn = .failure(OAuthError.accessDenied)
        let controller = AuthFlowController(oauthClient: oauthClient, tokenStore: FakeTokenStore())
        await controller.signIn()
        #expect(controller.state == .denied)

        controller.retry()

        #expect(controller.state == .notStarted)
    }
}
```

- [ ] **Step 3: Run the tests, verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: FAIL to compile — `AuthFlowController` doesn't exist yet.

- [ ] **Step 4: Implement `AuthFlowController`**

`TraxApp/Sources/TraxApp/AuthFlowController.swift`:
```swift
import Foundation
import KantataAPI

enum AuthFlowState: Equatable {
    case notStarted
    case waiting
    case signedIn
    case denied
    case failed(String)
}

@MainActor
@Observable
final class AuthFlowController {
    private(set) var state: AuthFlowState
    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore

    init(oauthClient: any OAuthClient, tokenStore: any TokenStore) {
        self.oauthClient = oauthClient
        self.tokenStore = tokenStore
        self.state = (try? tokenStore.load()) != nil ? .signedIn : .notStarted
    }

    func signIn() async {
        state = .waiting
        do {
            let token = try await oauthClient.signIn()
            try tokenStore.save(token)
            state = .signedIn
        } catch OAuthError.accessDenied {
            state = .denied
        } catch OAuthError.cancelled {
            state = .notStarted
        } catch {
            state = .failed("Something went wrong signing in. Please try again.")
        }
    }

    func cancel() {
        oauthClient.cancel()
        state = .notStarted
    }

    func retry() {
        state = .notStarted
    }
}
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from the repo root.
Expected: All `AuthFlowControllerTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift TraxApp/Sources/TraxApp/AuthFlowController.swift TraxApp/Tests/TraxAppTests/AuthFlowControllerTests.swift
git commit -m "$(cat <<'EOF'
Add AuthFlowController and wire KantataAPI into TraxApp

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: First-launch UI and auth gate

**Files:**
- Create: `TraxApp/Sources/TraxApp/FirstLaunchView.swift`
- Create: `TraxApp/Sources/TraxApp/AuthGateView.swift`
- Modify: `TraxApp/Sources/TraxApp/TraxApp.swift`

**Interfaces:**
- Consumes: `AuthFlowController`, `AuthFlowState` (Task 8), `LoopbackOAuthClient`, `OAuthConfig`, `URLSessionHTTPTransport`, `KeychainTokenStore`, `LoopbackListener` (`KantataAPI`).
- Produces: `FirstLaunchView`, `AuthGateView` — the new root content of `TraxApp`'s `WindowGroup`.

- [ ] **Step 1: Create `FirstLaunchView`**

`TraxApp/Sources/TraxApp/FirstLaunchView.swift`:
```swift
import SwiftUI

struct FirstLaunchView: View {
    var controller: AuthFlowController

    var body: some View {
        VStack(spacing: 16) {
            switch controller.state {
            case .notStarted:
                notStartedContent
            case .waiting:
                waitingContent
            case .denied:
                deniedContent
            case .failed(let message):
                failedContent(message)
            case .signedIn:
                EmptyView()
            }
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 360)
    }

    private var notStartedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
            Text("Connect your Kantata account")
                .font(.title2).bold()
            Text("Sign in to pull your scheduled tasks and push logged time and statuses back to Kantata.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Sign in with Kantata") {
                Task { await controller.signIn() }
            }
            .buttonStyle(.borderedProminent)
            Text("Opens your browser to sign in securely. You'll be redirected back here once you approve access.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var waitingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Waiting for you to sign in…")
            Button("Cancel") { controller.cancel() }
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 16) {
            Text("Access declined")
                .font(.title2).bold()
            Text("Trax needs access to your Kantata account to pull your schedule and log time. You can try again anytime.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") { controller.retry() }
        }
    }

    private func failedContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn't sign in")
                .font(.title2).bold()
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") { controller.retry() }
        }
    }
}
```

- [ ] **Step 2: Create `AuthGateView`**

`TraxApp/Sources/TraxApp/AuthGateView.swift`:
```swift
import SwiftUI
import KantataAPI

struct AuthGateView: View {
    @State private var controller: AuthFlowController

    init(oauthClient: any OAuthClient, tokenStore: any TokenStore) {
        _controller = State(initialValue: AuthFlowController(oauthClient: oauthClient, tokenStore: tokenStore))
    }

    var body: some View {
        if controller.state == .signedIn {
            TodayView()
        } else {
            FirstLaunchView(controller: controller)
        }
    }
}
```

- [ ] **Step 3: Wire `AuthGateView` into `TraxApp.swift`**

In `TraxApp/Sources/TraxApp/TraxApp.swift`, add `import KantataAPI` alongside the existing imports, and replace:

```swift
        WindowGroup {
            TodayView()
                .onAppear {
                    // Running as a bare executable (no .app bundle) means
                    // the process doesn't automatically get Dock/window
                    // focus — without this, the window can open off-screen
                    // or simply never come forward.
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(container)
```

with:

```swift
        WindowGroup {
            AuthGateView(
                oauthClient: LoopbackOAuthClient(
                    config: OAuthConfig(clientID: "REPLACE_WITH_REAL_CLIENT_ID"),
                    transport: URLSessionHTTPTransport(),
                    makeListener: { LoopbackListener(port: 51818) },
                    openBrowser: { NSWorkspace.shared.open($0) }
                ),
                tokenStore: KeychainTokenStore()
            )
            .onAppear {
                // Running as a bare executable (no .app bundle) means
                // the process doesn't automatically get Dock/window
                // focus — without this, the window can open off-screen
                // or simply never come forward.
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .modelContainer(container)
```

- [ ] **Step 4: Verify the package builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` from the repo root.
Expected: `Build complete!` with no errors.

- [ ] **Step 5: Commit**

```bash
git add TraxApp/Sources/TraxApp/FirstLaunchView.swift TraxApp/Sources/TraxApp/AuthGateView.swift TraxApp/Sources/TraxApp/TraxApp.swift
git commit -m "$(cat <<'EOF'
Add first-launch sign-in UI and gate the app on auth state

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** OAuth authorization-code flow with PKCE, loopback redirect — Tasks 1, 2, 4, 5. The three previously-undesigned first-launch states (waiting, denied, failed/expired) — Tasks 8, 9. Keychain token storage — Task 3. Typed API client for every resource `SPEC.md` § Relevant Kantata API resources lists as needed by this app — Tasks 6, 7. Auth gating the root view — Task 9. Explicitly out of scope per the design doc: real data flowing into `TodayView`, token refresh, `.app` bundle work — none of that is touched by any task.
- **Placeholder scan:** none found — every step has concrete, complete code. The literal string `"REPLACE_WITH_REAL_CLIENT_ID"` in Task 9 is intentional application config (documented in the design doc's Blocking external dependency section), not a plan placeholder.
- **Type consistency:** `PKCE` (Task 1) → consumed by `OAuthConfig.makeAuthorizationURL` (Task 2) and `LoopbackOAuthClient` (Task 5) with matching signatures. `OAuthToken`/`OAuthError` (Task 2) flow consistently through `KeychainTokenStore` (Task 3), `LoopbackOAuthClient` (Task 5), and `AuthFlowController` (Task 8). `CallbackListening` (Task 4) is the exact protocol `LoopbackOAuthClient`'s `makeListener` closure returns (Task 5). `HTTPTransport` (Task 2) is shared identically by `LoopbackOAuthClient` (Task 5) and `KantataAPIClient` (Task 7). `TokenStore` (Task 3) and `OAuthClient` (Task 5) are the exact two protocols `AuthFlowController` depends on (Task 8) and `AuthGateView` constructs real implementations of (Task 9).
