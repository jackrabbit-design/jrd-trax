import Foundation
import SwiftData
import Testing
@testable import TraxKit

@Suite("Model persistence round-trips")
@MainActor
struct ModelPersistenceTests {

    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Project round-trips")
    func projectRoundTrip() throws {
        let context = try makeContext()
        let project = Project(
            id: "p1",
            name: "Acme Redesign",
            colorHex: "#FF0000",
            workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/p1")!
        )
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "p1")
        #expect(fetched.first?.name == "Acme Redesign")
    }

    @Test("TraxTask round-trips")
    func taskRoundTrip() throws {
        let context = try makeContext()
        let task = TraxTask(
            id: "t1", projectId: "p1", name: "Design homepage",
            priority: .high, dueDate: nil, statusId: nil, storyId: "s1"
        )
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TraxTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.priority == .high)
        #expect(fetched.first?.statusId == nil)
    }

    @Test("Allocation round-trips")
    func allocationRoundTrip() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)
        let allocation = Allocation(id: "a1", taskId: "t1", date: date, scheduledMinutes: 90)
        context.insert(allocation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Allocation>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.scheduledMinutes == 90)
    }

    @Test("TimeEntry round-trips")
    func timeEntryRoundTrip() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)
        let entry = TimeEntry(taskId: "t1", date: date, minutes: 45)
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.synced == false)
        #expect(fetched.first?.minutes == 45)
    }

    @Test("Allocation date is normalized to the start of the local calendar day")
    func allocationDateIsNormalizedToStartOfDay() throws {
        let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
        let morning = dayStart.addingTimeInterval(3600 * 2)
        let evening = dayStart.addingTimeInterval(3600 * 20)

        let a = Allocation(id: "a1", taskId: "t1", date: morning, scheduledMinutes: 30)
        let b = Allocation(id: "a2", taskId: "t1", date: evening, scheduledMinutes: 60)

        #expect(a.date == b.date)
        #expect(a.date == dayStart)
    }

    @Test("Logging time against an unscheduled task creates no Allocation")
    func unscheduledTaskTimeEntryCreatesNoAllocation() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)
        let task = TraxTask(id: "t2", projectId: "p1", name: "Unscheduled task", priority: .none, storyId: "s2")
        context.insert(task)

        let entry = TimeEntry(taskId: "t2", date: date, minutes: 30)
        context.insert(entry)
        try context.save()

        let allocations = try context.fetch(
            FetchDescriptor<Allocation>(predicate: #Predicate { $0.taskId == "t2" })
        )
        #expect(allocations.isEmpty)

        let entries = try context.fetch(
            FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.taskId == "t2" })
        )
        #expect(entries.count == 1)
        #expect(entries.first?.minutes == 30)
    }

    @Test("TaskStatus round-trips")
    func taskStatusRoundTrip() throws {
        let context = try makeContext()
        let status = TaskStatus(id: "s1", projectId: "p1", name: "In Progress")
        context.insert(status)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TaskStatus>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.projectId == "p1")
        #expect(fetched.first?.name == "In Progress")
    }

    @Test("RunningTimer round-trips")
    func runningTimerRoundTrip() throws {
        let context = try makeContext()
        let startedAt = Date(timeIntervalSince1970: 1000)
        let timer = RunningTimer(taskId: "t1", startedAt: startedAt)
        context.insert(timer)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RunningTimer>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "current")
        #expect(fetched.first?.taskId == "t1")
        #expect(fetched.first?.startedAt == startedAt)
    }
}
