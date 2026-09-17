import SwiftUI
import AppKit
import SwiftData
import TraxKit

struct TaskRowView: View {
    let task: TraxTask
    let date: Date
    let status: TaskStatus?
    let statusOptions: [TaskStatus]
    let scheduledMinutes: Int?
    let loggedMinutes: Int

    @Query private var runningTimers: [RunningTimer]
    @Environment(\.modelContext) private var modelContext

    @State private var isAddingTime = false
    @State private var durationFieldState = DurationFieldState()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    startTimer()
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                priorityDot
                Button {
                    openTaskLink()
                } label: {
                    HStack(spacing: 4) {
                        Text(task.name)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .frame(minWidth: 160, alignment: .leading)

                Text(dueLabel)
                    .font(.caption)
                    .foregroundStyle(task.dueDate == nil ? .secondary : .primary)
                    .frame(width: 70, alignment: .leading)

                scheduledLabel
                    .frame(width: 70, alignment: .leading)

                Text(DurationFormatting.short(loggedMinutes))
                    .font(.caption)
                    .frame(width: 70, alignment: .leading)

                StatusDropdown(task: task, currentStatus: status, options: statusOptions)
                    .frame(width: 140, alignment: .leading)

                Button {
                    isAddingTime.toggle()
                    if !isAddingTime { durationFieldState.reset() }
                } label: {
                    Image(systemName: isAddingTime ? "xmark" : "plus")
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if isAddingTime {
                QuickAddTimeField(
                    state: durationFieldState,
                    placeholder: "1h30m",
                    submitLabel: "Log"
                ) { minutes in
                    logTime(minutes)
                    isAddingTime = false
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }

    private var priorityDot: some View {
        Circle()
            .fill(priorityColor ?? Color.clear)
            .frame(width: 8, height: 8)
    }

    private var priorityColor: Color? {
        switch task.priority {
        case .critical: return .red
        case .high: return .orange
        case .normal: return .gray
        case .low: return Color.gray.opacity(0.5)
        case .none: return nil
        }
    }

    private var dueLabel: String {
        guard let dueDate = task.dueDate else { return "—" }
        return DueDateFormatting.short(dueDate, relativeTo: .now)
    }

    private var scheduledLabel: some View {
        Group {
            if let scheduledMinutes {
                Text(DurationFormatting.short(scheduledMinutes))
                    .font(.caption)
            } else {
                Text("—")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openTaskLink() {
        guard let url = URL(string: "https://app.mavenlink.com/workspaces/\(task.projectId)/stories/\(task.storyId)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var isRunning: Bool {
        runningTimers.first?.taskId == task.id
    }

    private func startTimer() {
        if let existing = runningTimers.first {
            modelContext.delete(existing)
        }
        modelContext.insert(RunningTimer(taskId: task.id, startedAt: .now))
        try? modelContext.save()
    }

    private func logTime(_ minutes: Int) {
        let entry = TimeEntry(taskId: task.id, date: date, minutes: minutes)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}
