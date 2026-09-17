import SwiftUI
import KantataAPI

struct AuthGateView: View {
    @State private var controller: AuthFlowController
    private let apiClient: KantataAPIClient

    init(oauthClient: any OAuthClient, tokenStore: any TokenStore) {
        _controller = State(initialValue: AuthFlowController(oauthClient: oauthClient, tokenStore: tokenStore))
        apiClient = KantataAPIClient(
            transport: URLSessionHTTPTransport(),
            tokenProvider: { try? tokenStore.load()?.accessToken }
        )
    }

    var body: some View {
        if controller.state == .signedIn {
            TodayView(apiClient: apiClient)
        } else {
            FirstLaunchView(controller: controller)
        }
    }
}
