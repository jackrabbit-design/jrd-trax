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
