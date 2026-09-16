import SwiftUI
import SwiftData
import TraxKit

struct RunningTimerBanner: View {
    @Query private var runningTimers: [RunningTimer]
    @Query private var tasks: [TraxTask]
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var now: Date = .now
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var runningTimer: RunningTimer? { runningTimers.first }

    private var task: TraxTask? {
        guard let runningTimer else { return nil }
        return tasks.first { $0.id == runningTimer.taskId }
    }

    private var project: Project? {
        guard let task else { return nil }
        return projects.first { $0.id == task.projectId }
    }

    private var elapsed: TimeInterval {
        guard let runningTimer else { return 0 }
        return now.timeIntervalSince(runningTimer.startedAt)
    }

    var body: some View {
        if let runningTimer, let task {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(task.name)
                        .font(.headline)
                }
                Spacer()
                Text(elapsedLabel)
                    .font(.system(.body, design: .monospaced))
                Button("Stop") {
                    stop(runningTimer)
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.15))
            .onReceive(ticker) { tick in now = tick }
        }
    }

    private var elapsedLabel: String {
        let totalSeconds = max(0, Int(elapsed))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func stop(_ runningTimer: RunningTimer) {
        let elapsedMinutes = RunningTimerLogic.elapsedMinutes(from: runningTimer.startedAt, to: now)
        if elapsedMinutes > 0 {
            let entry = TimeEntry(
                taskId: runningTimer.taskId,
                date: Calendar.current.startOfDay(for: .now),
                minutes: elapsedMinutes
            )
            modelContext.insert(entry)
        }
        modelContext.delete(runningTimer)
        try? modelContext.save()
    }
}
