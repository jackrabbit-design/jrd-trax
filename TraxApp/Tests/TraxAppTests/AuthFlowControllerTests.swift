import Foundation
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
        OAuthToken(accessToken: "tok", tokenType: "Bearer", scope: nil, refreshToken: nil, createdAt: Date(timeIntervalSince1970: 0))
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
