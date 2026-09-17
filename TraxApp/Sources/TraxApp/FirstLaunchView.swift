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
