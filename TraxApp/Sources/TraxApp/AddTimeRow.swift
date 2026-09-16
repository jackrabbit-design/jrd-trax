import SwiftUI
import SwiftData
import TraxKit

struct AddTimeRow: View {
    let date: Date

    @Query private var projects: [Project]
    @Query private var tasks: [TraxTask]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProjectId: String?
    @State private var taskQuery: String = ""
    @State private var selectedTaskId: String?
    @State private var durationFieldState = DurationFieldState()

    private var tasksForSelectedProject: [TraxTask] {
        guard let selectedProjectId else { return [] }
        let base = tasks.filter { $0.projectId == selectedProjectId }
        guard !taskQuery.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(taskQuery) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Project", selection: $selectedProjectId) {
                Text("Choose a project").tag(String?.none)
                ForEach(projects, id: \.id) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .frame(width: 160)
            .onChange(of: selectedProjectId) {
                selectedTaskId = nil
                taskQuery = ""
            }

            if selectedProjectId != nil {
                TextField("Search tasks", text: $taskQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                Picker("Task", selection: $selectedTaskId) {
                    Text("Choose a task").tag(String?.none)
                    ForEach(tasksForSelectedProject, id: \.id) { task in
                        Text(task.name).tag(Optional(task.id))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            QuickAddTimeField(
                state: durationFieldState,
                placeholder: "1h30m",
                submitLabel: "Add",
                isEnabled: selectedTaskId != nil
            ) { minutes in
                addTime(minutes)
            }
        }
        .padding()
    }

    private func addTime(_ minutes: Int) {
        guard let selectedTaskId else { return }
        let entry = TimeEntry(taskId: selectedTaskId, date: date, minutes: minutes)
        modelContext.insert(entry)
        try? modelContext.save()
        self.selectedTaskId = nil
        taskQuery = ""
    }
}
