import Foundation
import SwiftData
import TraxKit

enum SampleData {
    @MainActor
    static func seed(into container: ModelContainer) {
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: .now)

        let design = Project(
            id: "p1", name: "Acme Redesign", colorHex: "#4F46E5",
            workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/p1")!
        )
        let launch = Project(
            id: "p2", name: "Product Launch", colorHex: "#059669",
            workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/p2")!
        )
        context.insert(design)
        context.insert(launch)

        let inProgress = TaskStatus(id: "s1", projectId: "p1", name: "In Progress")
        let blocked = TaskStatus(id: "s2", projectId: "p1", name: "Blocked")
        let todo = TaskStatus(id: "s3", projectId: "p2", name: "To Do")
        context.insert(inProgress)
        context.insert(blocked)
        context.insert(todo)

        let homepage = TraxTask(
            id: "t1", projectId: "p1", name: "Design homepage",
            priority: .critical, dueDate: today, statusId: "s1", storyId: "st1"
        )
        let onboarding = TraxTask(
            id: "t2", projectId: "p1", name: "Revise onboarding flow",
            priority: .normal, dueDate: today.addingTimeInterval(86400 * 3),
            statusId: "s2", storyId: "st2"
        )
        let brief = TraxTask(
            id: "t3", projectId: "p1", name: "Write creative brief",
            priority: .none, dueDate: nil, statusId: nil, storyId: "st3"
        )
        let pressRelease = TraxTask(
            id: "t4", projectId: "p2", name: "Draft press release",
            priority: .high, dueDate: today, statusId: "s3", storyId: "st4"
        )
        [homepage, onboarding, brief, pressRelease].forEach { context.insert($0) }

        context.insert(Allocation(id: "a1", taskId: "t1", date: today, scheduledMinutes: 120))
        context.insert(Allocation(id: "a2", taskId: "t4", date: today, scheduledMinutes: 60))
        // t2 and t3 are assigned but have no allocation for today — the
        // mixed scheduled/unscheduled case from SPEC.md.

        try? context.save()
    }
}
