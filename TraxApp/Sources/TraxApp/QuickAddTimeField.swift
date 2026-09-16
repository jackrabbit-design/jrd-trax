import SwiftUI

struct QuickAddTimeField: View {
    @Bindable var state: DurationFieldState
    let placeholder: String
    let submitLabel: String
    var isEnabled: Bool = true
    let onSubmit: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $state.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { submit() }

                if let previewMinutes = state.previewMinutes {
                    Text("= \(previewMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(submitLabel) { submit() }
                    .disabled(!state.canSubmit || !isEnabled)
            }
            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        guard isEnabled else { return }
        if let minutes = state.validate() {
            onSubmit(minutes)
            state.reset()
        }
    }
}
