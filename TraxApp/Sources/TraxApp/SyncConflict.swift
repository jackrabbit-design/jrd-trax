struct ConflictCheckInput: Sendable {
    let taskId: String
    let taskName: String
    let syncedStatusId: String?
    let localStatusId: String?
    let localStatusName: String
    let remoteStatusId: String?
    let remoteStatusName: String
}

struct SyncConflict: Sendable, Equatable, Identifiable {
    var id: String { taskId }
    let taskId: String
    let taskName: String
    let localStatusId: String?
    let localStatusName: String
    let remoteStatusId: String?
    let remoteStatusName: String
}

enum ConflictResolution: Sendable, Equatable {
    case keepMine
    case useKantatas
}

func detectConflicts(_ inputs: [ConflictCheckInput]) -> [SyncConflict] {
    inputs.compactMap { input in
        guard let baseline = input.syncedStatusId else { return nil }
        let localChanged = input.localStatusId != baseline
        let remoteChanged = input.remoteStatusId != baseline
        guard localChanged, remoteChanged, input.localStatusId != input.remoteStatusId else { return nil }
        return SyncConflict(
            taskId: input.taskId,
            taskName: input.taskName,
            localStatusId: input.localStatusId,
            localStatusName: input.localStatusName,
            remoteStatusId: input.remoteStatusId,
            remoteStatusName: input.remoteStatusName
        )
    }
}
