import SwiftUI
import SwiftData
import AppKit
import TraxKit
import KantataAPI

@MainActor
public struct TraxAppMain: App {
    let container: ModelContainer

    public init() {
        do {
            container = try PersistenceController.makeContainer(inMemory: true)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        let context = container.mainContext
        let existingProjectCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        if existingProjectCount == 0 {
            SampleData.seed(into: container)
        }
    }

    public var body: some Scene {
        WindowGroup {
            AuthGateView(
                oauthClient: LoopbackOAuthClient(
                    config: OAuthConfig(
                        clientID: "ffc0ff2474480c66244a3541ee0bb465aa3d1e73699ad877c710840f91484a53",
                        clientSecret: "REPLACE_WITH_REAL_CLIENT_SECRET"
                    ),
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
    }
}
