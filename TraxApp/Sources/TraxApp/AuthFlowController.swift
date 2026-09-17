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
        } catch let error as OAuthError {
            state = .failed(Self.message(for: error))
        } catch let KeychainError.status(status) {
            state = .failed("Couldn't save your sign-in to the Keychain (status \(status)).")
        } catch {
            state = .failed("Something went wrong signing in: \(error.localizedDescription)")
        }
    }

    private static func message(for error: OAuthError) -> String {
        switch error {
        case .exchangeFailed(let detail):
            return "Couldn't complete sign-in: \(detail)"
        case .missingAuthorizationCode:
            return "Kantata didn't return an authorization code. Please try again."
        case .stateMismatch:
            return "Sign-in response didn't match the request. Please try again."
        case .listenerFailed(let detail):
            return "Couldn't start the local sign-in listener: \(detail)"
        case .unauthorized:
            return "Your Kantata session is no longer valid. Please try again."
        case .accessDenied, .cancelled:
            return "Something went wrong signing in. Please try again."
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
