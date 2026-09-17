import Testing
@testable import TraxApp

@Suite("Conflict detection")
struct SyncConflictTests {
    private func input(
        localStatusId: String?,
        syncedStatusId: String?,
        remoteStatusId: String?
    ) -> ConflictCheckInput {
        ConflictCheckInput(
            taskId: "t1", taskName: "Design homepage",
            syncedStatusId: syncedStatusId,
            localStatusId: localStatusId, localStatusName: localStatusId ?? "No status",
            remoteStatusId: remoteStatusId, remoteStatusName: remoteStatusId ?? "No status"
        )
    }

    @Test("no conflict when only the local value changed")
    func localOnlyChange() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: "s1", remoteStatusId: "s1")])
        #expect(result.isEmpty)
    }

    @Test("no conflict when only the remote value changed")
    func remoteOnlyChange() {
        let result = detectConflicts([input(localStatusId: "s1", syncedStatusId: "s1", remoteStatusId: "s2")])
        #expect(result.isEmpty)
    }

    @Test("no conflict when both changed to the same value")
    func bothChangedSameValue() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: "s1", remoteStatusId: "s2")])
        #expect(result.isEmpty)
    }

    @Test("conflict when both changed to different values")
    func bothChangedDifferentValues() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: "s1", remoteStatusId: "s3")])
        #expect(result.count == 1)
        #expect(result.first?.localStatusId == "s2")
        #expect(result.first?.remoteStatusId == "s3")
    }

    @Test("no conflict when there is no baseline (never synced)")
    func neverSyncedNoBaseline() {
        let result = detectConflicts([input(localStatusId: "s2", syncedStatusId: nil, remoteStatusId: "s3")])
        #expect(result.isEmpty)
    }

    @Test("no conflict when neither side changed")
    func noChange() {
        let result = detectConflicts([input(localStatusId: "s1", syncedStatusId: "s1", remoteStatusId: "s1")])
        #expect(result.isEmpty)
    }
}
