import SwiftUI
import SwiftData
import TraxKit

struct TaskListView: View {
    let selectedDate: Date

    @Query private var projects: [Project]
    @Query private var tasks: [TraxTask]
    @Query private var allocations: [Allocation]
    @Query private var timeEntries: [TimeEntry]
    @Query private var statuses: [TaskStatus]

    private var groupedTasks: [(project: Project, tasks: [TraxTask])] {
        projects
            .sorted { $0.name < $1.name }
            .map { project in
                let tasksForProject = tasks.filter { $0.projectId == project.id }
                return (project, TaskSorting.sorted(tasksForProject))
            }
            .filter { !$0.tasks.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groupedTasks, id: \.project.id) { group in
                    ProjectHeaderRow(
                        project: group.project,
                        scheduledMinutes: totalScheduled(for: group.project),
                        loggedMinutes: totalLogged(for: group.project)
                    )
                    ForEach(group.tasks, id: \.id) { task in
                        TaskRowView(
                            task: task,
                            date: selectedDate,
                            status: statuses.first { $0.id == task.statusId },
                            statusOptions: statuses.filter { $0.projectId == task.projectId },
                            scheduledMinutes: scheduledMinutes(for: task),
                            loggedMinutes: loggedMinutes(for: task)
                        )
                    }
                }
            }
            .padding()
        }
    }

    private func scheduledMinutes(for task: TraxTask) -> Int? {
        allocations.first { $0.taskId == task.id && $0.date == selectedDate }?.scheduledMinutes
    }

    private func loggedMinutes(for task: TraxTask) -> Int {
        timeEntries.filter { $0.taskId == task.id && $0.date == selectedDate }.reduce(0) { $0 + $1.minutes }
    }

    private func totalScheduled(for project: Project) -> Int {
        tasks.filter { $0.projectId == project.id }
            .compactMap { scheduledMinutes(for: $0) }
            .reduce(0, +)
    }

    private func totalLogged(for project: Project) -> Int {
        tasks.filter { $0.projectId == project.id }
            .map { loggedMinutes(for: $0) }
            .reduce(0, +)
    }
}
