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
