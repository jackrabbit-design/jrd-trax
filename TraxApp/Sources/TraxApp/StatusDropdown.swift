import SwiftUI
import SwiftData
import TraxKit

struct StatusDropdown: View {
    let task: TraxTask
    let currentStatus: TaskStatus?
    let options: [TaskStatus]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if task.statusId == nil {
            Text("No status")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Status", selection: Binding(
                get: { task.statusId },
                set: { newValue in
                    task.statusId = newValue
                    try? modelContext.save()
                }
            )) {
                ForEach(options, id: \.id) { option in
                    Text(option.name).tag(Optional(option.id))
                }
            }
            .labelsHidden()
            .font(.caption)
        }
    }
}
