import Foundation
import SwiftData
import TraxKit
import KantataAPI

struct SyncPreparation: Sendable {
    let remoteStatuses: [TaskStatusDTO]
    let remoteStatusSets: [StatusSetDTO]
    let remoteAssignments: [AssignmentDTO]
    let remoteStories: [StoryDTO]
    let remoteWorkspaces: [WorkspaceDTO]
    let remoteAllocations: [DailyScheduledHourDTO]
    let conflicts: [SyncConflict]
    let dateWindow: (from: String, to: String)
}

enum SyncError: Error, Equatable {
    case partialFailure([String])
    case missingResolution(String)
}

@MainActor
final class SyncEngine {
    private let modelContext: ModelContext
    private let apiClient: KantataAPIClient
    private let pastWindowDays: Int
    private let futureWindowDays: Int

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(
        modelContext: ModelContext,
        apiClient: KantataAPIClient,
        pastWindowDays: Int = 7,
        futureWindowDays: Int = 14
    ) {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.pastWindowDays = pastWindowDays
        self.futureWindowDays = futureWindowDays
    }

    func prepareSync() async throws -> SyncPreparation {
        let remoteStatuses = try await apiClient.fetchTaskStatuses()
        let remoteStatusSets = try await apiClient.fetchStatusSets()
        let remoteAssignments = try await apiClient.fetchAssignments()
        let remoteStories = try await apiClient.fetchStories()
        let remoteWorkspaces = try await apiClient.fetchWorkspaces()
        let (from, to) = dateWindow()
        let remoteAllocations = try await apiClient.fetchDailyScheduledHours(from: from, to: to)

        let localTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        let localStatuses = try modelContext.fetch(FetchDescriptor<TaskStatus>())
        let localStatusNamesById = Dictionary(uniqueKeysWithValues: localStatuses.map { ($0.id, $0.name) })
        let remoteStatusNamesById = Dictionary(remoteStatuses.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })
        let remoteStoriesById = Dictionary(remoteStories.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        let inputs: [ConflictCheckInput] = localTasks.compactMap { task in
            guard let remoteStory = remoteStoriesById[task.id] else { return nil }
            return ConflictCheckInput(
                taskId: task.id,
                taskName: task.name,
                syncedStatusId: task.syncedStatusId,
                localStatusId: task.statusId,
                localStatusName: Self.statusName(for: task.statusId, in: localStatusNamesById),
                remoteStatusId: remoteStory.statusId,
                remoteStatusName: Self.statusName(for: remoteStory.statusId, in: remoteStatusNamesById)
            )
        }

        return SyncPreparation(
            remoteStatuses: remoteStatuses,
            remoteStatusSets: remoteStatusSets,
            remoteAssignments: remoteAssignments,
            remoteStories: remoteStories,
            remoteWorkspaces: remoteWorkspaces,
            remoteAllocations: remoteAllocations,
            conflicts: detectConflicts(inputs),
            dateWindow: (from, to)
        )
    }

    func applySync(_ preparation: SyncPreparation, resolutions: [String: ConflictResolution]) async throws {
        for conflict in preparation.conflicts {
            guard resolutions[conflict.taskId] != nil else {
                throw SyncError.missingResolution(conflict.taskId)
            }
        }

        var useKantatasTaskIds: Set<String> = []
        for conflict in preparation.conflicts {
            guard let resolution = resolutions[conflict.taskId] else { continue }
            if resolution == .useKantatas {
                useKantatasTaskIds.insert(conflict.taskId)
                if let task = try taskById(conflict.taskId) {
                    task.statusId = conflict.remoteStatusId
                }
            }
        }

        var failures: [String] = []
        var failedStatusPushTaskIds: Set<String> = []

        let unsyncedEntries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.synced == false })
        )
        for entry in unsyncedEntries {
            guard let task = try taskById(entry.taskId) else {
                failures.append("time entry for unknown task \(entry.taskId)")
                continue
            }
            do {
                let dateString = Self.isoDateFormatter.string(from: entry.date)
                let hours = Double(entry.minutes) / 60
                _ = try await apiClient.createTimeEntry(
                    TimeEntryCreateRequest(storyId: task.storyId, date: dateString, hours: hours)
                )
                entry.synced = true
            } catch let error as KantataAPIError where error == .unauthorized {
                try? modelContext.save()
                throw error
            } catch {
                failures.append("time entry for \(entry.taskId)")
            }
        }

        let localTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        for task in localTasks {
            guard !useKantatasTaskIds.contains(task.id) else { continue }
            guard task.syncedStatusId != nil else { continue }
            guard task.statusId != task.syncedStatusId, let newStatusId = task.statusId else { continue }
            do {
                _ = try await apiClient.createStoryStateChange(
                    StoryStateChangeCreateRequest(storyId: task.storyId, statusId: newStatusId)
                )
            } catch let error as KantataAPIError where error == .unauthorized {
                try? modelContext.save()
                throw error
            } catch {
                failures.append("status for \(task.name)")
                failedStatusPushTaskIds.insert(task.id)
            }
        }

        let existingStatuses = try modelContext.fetch(FetchDescriptor<TaskStatus>())
        var existingStatusesById = Dictionary(existingStatuses.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var seenStatusIds: Set<String> = []
        let statusNamesById = Dictionary(preparation.remoteStatuses.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })
        for statusSet in preparation.remoteStatusSets {
            for statusId in statusSet.statusIds {
                guard let name = statusNamesById[statusId] else { continue }
                seenStatusIds.insert(statusId)
                if let existing = existingStatusesById[statusId] {
                    existing.name = name
                    existing.projectId = statusSet.workspaceId
                } else {
                    let newStatus = TaskStatus(id: statusId, projectId: statusSet.workspaceId, name: name)
                    modelContext.insert(newStatus)
                    existingStatusesById[statusId] = newStatus
                }
            }
        }
        for status in existingStatuses where !seenStatusIds.contains(status.id) {
            modelContext.delete(status)
        }

        let existingProjects = try modelContext.fetch(FetchDescriptor<Project>())
        var existingProjectsById = Dictionary(existingProjects.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for workspace in preparation.remoteWorkspaces {
            if let existing = existingProjectsById[workspace.id] {
                existing.name = workspace.title
            } else {
                let newProject = Project(
                    id: workspace.id,
                    name: workspace.title,
                    colorHex: "#6B7280",
                    workspaceURL: URL(string: "https://app.mavenlink.com/workspaces/\(workspace.id)")!
                )
                modelContext.insert(newProject)
                existingProjectsById[workspace.id] = newProject
            }
        }

        let storiesById = Dictionary(preparation.remoteStories.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let refreshedLocalTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        let localTasksById = Dictionary(uniqueKeysWithValues: refreshedLocalTasks.map { ($0.id, $0) })
        for assignment in preparation.remoteAssignments {
            guard let story = storiesById[assignment.storyId] else { continue }
            if let existing = localTasksById[story.id] {
                existing.name = story.title
                existing.priority = Self.priority(from: story.priority)
                existing.dueDate = story.dueDate.flatMap { Self.isoDateFormatter.date(from: $0) }
            } else {
                modelContext.insert(TraxTask(
                    id: story.id,
                    projectId: story.workspaceId,
                    name: story.title,
                    priority: Self.priority(from: story.priority),
                    dueDate: story.dueDate.flatMap { Self.isoDateFormatter.date(from: $0) },
                    statusId: story.statusId,
                    storyId: story.id,
                    syncedStatusId: story.statusId
                ))
            }
        }

        let (from, to) = preparation.dateWindow
        var existingAllocationsById: [String: Allocation] = [:]
        var seenAllocationIds: Set<String> = []
        if let fromDate = Self.isoDateFormatter.date(from: from), let toDate = Self.isoDateFormatter.date(from: to) {
            let existingAllocations = try modelContext.fetch(
                FetchDescriptor<Allocation>(predicate: #Predicate { $0.date >= fromDate && $0.date <= toDate })
            )
            existingAllocationsById = Dictionary(existingAllocations.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        }
        for dto in preparation.remoteAllocations {
            guard let date = Self.isoDateFormatter.date(from: dto.date) else { continue }
            seenAllocationIds.insert(dto.id)
            let minutes = Int((dto.hours * 60).rounded())
            if let existing = existingAllocationsById[dto.id] {
                existing.taskId = dto.storyId
                existing.date = date
                existing.scheduledMinutes = minutes
            } else {
                modelContext.insert(Allocation(id: dto.id, taskId: dto.storyId, date: date, scheduledMinutes: minutes))
            }
        }
        for (id, allocation) in existingAllocationsById where !seenAllocationIds.contains(id) {
            modelContext.delete(allocation)
        }

        for task in localTasks {
            guard !useKantatasTaskIds.contains(task.id) else { continue }
            guard task.statusId == task.syncedStatusId else { continue }
            guard let remoteStory = storiesById[task.id], let remoteStatusId = remoteStory.statusId, remoteStatusId != task.statusId else { continue }
            task.statusId = remoteStatusId
        }

        let finalTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        for task in finalTasks where !failedStatusPushTaskIds.contains(task.id) {
            task.syncedStatusId = task.statusId
        }

        let syncStates = try modelContext.fetch(FetchDescriptor<SyncState>())
        let syncState = syncStates.first ?? SyncState()
        if syncStates.isEmpty {
            modelContext.insert(syncState)
        }
        syncState.lastSyncedAt = .now

        try modelContext.save()

        if !failures.isEmpty {
            throw SyncError.partialFailure(failures)
        }
    }

    private func taskById(_ id: String) throws -> TraxTask? {
        try modelContext.fetch(FetchDescriptor<TraxTask>(predicate: #Predicate { $0.id == id })).first
    }

    private func dateWindow() -> (from: String, to: String) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let from = calendar.date(byAdding: .day, value: -pastWindowDays, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: futureWindowDays, to: today) ?? today
        return (Self.isoDateFormatter.string(from: from), Self.isoDateFormatter.string(from: to))
    }

    private static func statusName(for id: String?, in namesById: [String: String]) -> String {
        guard let id else { return "No status" }
        return namesById[id] ?? "Unknown status"
    }

    private static func priority(from raw: String?) -> Priority {
        switch raw?.lowercased() {
        case "critical": return .critical
        case "high": return .high
        case "normal": return .normal
        case "low": return .low
        default: return .none
        }
    }
}
