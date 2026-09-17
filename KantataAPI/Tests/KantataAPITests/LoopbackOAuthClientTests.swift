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

        nonisolated(unsafe) var openedURL: URL?
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
