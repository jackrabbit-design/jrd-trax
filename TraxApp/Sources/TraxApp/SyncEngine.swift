import Foundation
import SwiftData
import TraxKit
import KantataAPI

struct SyncPreparation: Sendable {
    let remoteStatuses: [TaskStatusDTO]
    let remoteStatusSets: [StatusSetDTO]
    let remoteAssignments: [AssignmentDTO]
    let remoteStories: [StoryDTO]
    let remoteAllocations: [DailyScheduledHourDTO]
    let conflicts: [SyncConflict]
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
        let (from, to) = dateWindow()
        let remoteAllocations = try await apiClient.fetchDailyScheduledHours(from: from, to: to)

        let localTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        let localStatuses = try modelContext.fetch(FetchDescriptor<TaskStatus>())
        let localStatusNamesById = Dictionary(uniqueKeysWithValues: localStatuses.map { ($0.id, $0.name) })
        let remoteStatusNamesById = Dictionary(uniqueKeysWithValues: remoteStatuses.map { ($0.id, $0.name) })
        let remoteStoriesById = Dictionary(uniqueKeysWithValues: remoteStories.map { ($0.id, $0) })

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
            remoteAllocations: remoteAllocations,
            conflicts: detectConflicts(inputs)
        )
    }

    func applySync(_ preparation: SyncPreparation, resolutions: [String: ConflictResolution]) async throws {
        var useKantatasTaskIds: Set<String> = []
        for conflict in preparation.conflicts {
            guard let resolution = resolutions[conflict.taskId] else {
                throw SyncError.missingResolution(conflict.taskId)
            }
            if resolution == .useKantatas {
                useKantatasTaskIds.insert(conflict.taskId)
                if let task = try taskById(conflict.taskId) {
                    task.statusId = conflict.remoteStatusId
                }
            }
        }

        var failures: [String] = []

        let unsyncedEntries = try modelContext.fetch(
            FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.synced == false })
        )
        for entry in unsyncedEntries {
            do {
                let dateString = Self.isoDateFormatter.string(from: entry.date)
                let hours = Double(entry.minutes) / 60
                _ = try await apiClient.createTimeEntry(
                    TimeEntryCreateRequest(storyId: entry.taskId, date: dateString, hours: hours)
                )
                entry.synced = true
            } catch {
                failures.append("time entry for \(entry.taskId)")
            }
        }

        let localTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        for task in localTasks {
            guard !useKantatasTaskIds.contains(task.id) else { continue }
            guard task.statusId != task.syncedStatusId, let newStatusId = task.statusId else { continue }
            do {
                _ = try await apiClient.createStoryStateChange(
                    StoryStateChangeCreateRequest(storyId: task.storyId, statusId: newStatusId)
                )
            } catch {
                failures.append("status for \(task.name)")
            }
        }

        let existingStatuses = try modelContext.fetch(FetchDescriptor<TaskStatus>())
        for status in existingStatuses {
            modelContext.delete(status)
        }
        let statusNamesById = Dictionary(uniqueKeysWithValues: preparation.remoteStatuses.map { ($0.id, $0.name) })
        for statusSet in preparation.remoteStatusSets {
            for statusId in statusSet.statusIds {
                guard let name = statusNamesById[statusId] else { continue }
                modelContext.insert(TaskStatus(id: statusId, projectId: statusSet.workspaceId, name: name))
            }
        }

        let storiesById = Dictionary(uniqueKeysWithValues: preparation.remoteStories.map { ($0.id, $0) })
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

        let (from, to) = dateWindow()
        if let fromDate = Self.isoDateFormatter.date(from: from), let toDate = Self.isoDateFormatter.date(from: to) {
            let existingAllocations = try modelContext.fetch(
                FetchDescriptor<Allocation>(predicate: #Predicate { $0.date >= fromDate && $0.date <= toDate })
            )
            for allocation in existingAllocations {
                modelContext.delete(allocation)
            }
        }
        for dto in preparation.remoteAllocations {
            guard let date = Self.isoDateFormatter.date(from: dto.date) else { continue }
            modelContext.insert(Allocation(
                id: dto.id, taskId: dto.storyId, date: date,
                scheduledMinutes: Int((dto.hours * 60).rounded())
            ))
        }

        let finalTasks = try modelContext.fetch(FetchDescriptor<TraxTask>())
        for task in finalTasks {
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
