import Foundation
import Testing
import TraxKit
@testable import TraxApp

@Suite("Task sorting")
struct TaskSortingTests {
    @Test("sorts by priority tier, critical first, none last")
    func sortsByPriority() {
        let low = TraxTask(id: "low", projectId: "p", name: "Low", priority: .low, storyId: "s1")
        let critical = TraxTask(id: "crit", projectId: "p", name: "Critical", priority: .critical, storyId: "s2")
        let none = TraxTask(id: "none", projectId: "p", name: "None", priority: .none, storyId: "s3")
        let high = TraxTask(id: "high", projectId: "p", name: "High", priority: .high, storyId: "s4")

        let sorted = TaskSorting.sorted([low, none, critical, high])
        #expect(sorted.map(\.id) == ["crit", "high", "low", "none"])
    }

    @Test("within a priority tier, sorts by due date ascending, no due date last")
    func sortsByDueDateWithinTier() {
        let today = Calendar.current.startOfDay(for: .now)
        let soon = TraxTask(id: "soon", projectId: "p", name: "Soon", priority: .normal, dueDate: today, storyId: "s1")
        let later = TraxTask(id: "later", projectId: "p", name: "Later", priority: .normal, dueDate: today.addingTimeInterval(86400 * 5), storyId: "s2")
        let noDue = TraxTask(id: "noDue", projectId: "p", name: "No due", priority: .normal, storyId: "s3")

        let sorted = TaskSorting.sorted([noDue, later, soon])
        #expect(sorted.map(\.id) == ["soon", "later", "noDue"])
    }

    @Test("priority tier takes precedence over due date")
    func priorityBeatsDueDate() {
        let today = Calendar.current.startOfDay(for: .now)
        let highNoDue = TraxTask(id: "highNoDue", projectId: "p", name: "High, no due", priority: .high, storyId: "s1")
        let normalDueToday = TraxTask(id: "normalDueToday", projectId: "p", name: "Normal, due today", priority: .normal, dueDate: today, storyId: "s2")

        let sorted = TaskSorting.sorted([normalDueToday, highNoDue])
        #expect(sorted.map(\.id) == ["highNoDue", "normalDueToday"])
    }
}
