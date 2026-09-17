import SwiftUI

private extension View {
    @ViewBuilder
    func conflictChoiceStyle(isSelected: Bool) -> some View {
        if isSelected {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

struct ConflictResolutionView: View {
    let conflicts: [SyncConflict]
    let onApply: ([String: ConflictResolution]) -> Void
    let onCancel: () -> Void

    @State private var resolutions: [String: ConflictResolution] = [:]

    private var allResolved: Bool {
        conflicts.allSatisfy { resolutions[$0.taskId] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resolve conflicts")
                .font(.title2)
                .bold()
            Text("These fields changed both locally and on Kantata since your last sync.")
                .foregroundStyle(.secondary)

            ForEach(conflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.taskName)
                        .font(.headline)
                    HStack {
                        Button("Keep mine (\(conflict.localStatusName))") {
                            resolutions[conflict.taskId] = .keepMine
                        }
                        .conflictChoiceStyle(isSelected: resolutions[conflict.taskId] == .keepMine)

                        Button("Use Kantata's (\(conflict.remoteStatusName))") {
                            resolutions[conflict.taskId] = .useKantatas
                        }
                        .conflictChoiceStyle(isSelected: resolutions[conflict.taskId] == .useKantatas)
                    }
                    if resolutions[conflict.taskId] == nil {
                        Text("Choose one")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button("Cancel sync", role: .destructive) {
                    onCancel()
                }
                Spacer()
                Button("Apply and continue sync") {
                    onApply(resolutions)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allResolved)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
