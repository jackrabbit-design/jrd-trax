import Foundation
import KantataAPI

enum SyncPhase: Equatable {
    case idle
    case syncing
    case conflicts([SyncConflict])
    case failed(String)
}

@MainActor
@Observable
final class SyncController {
    private(set) var phase: SyncPhase = .idle
    private let engine: SyncEngine
    private var pendingPreparation: SyncPreparation?

    init(engine: SyncEngine) {
        self.engine = engine
    }

    var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
    }

    func startSync() async {
        phase = .syncing
        do {
            let preparation = try await engine.prepareSync()
            if preparation.conflicts.isEmpty {
                try await engine.applySync(preparation, resolutions: [:])
                phase = .idle
            } else {
                pendingPreparation = preparation
                phase = .conflicts(preparation.conflicts)
            }
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func resolveConflicts(_ resolutions: [String: ConflictResolution]) async {
        guard let preparation = pendingPreparation else { return }
        phase = .syncing
        do {
            try await engine.applySync(preparation, resolutions: resolutions)
            phase = .idle
            pendingPreparation = nil
        } catch {
            phase = .failed(Self.message(for: error))
            pendingPreparation = nil
        }
    }

    func cancelConflicts() {
        pendingPreparation = nil
        phase = .idle
    }

    func dismissFailure() {
        phase = .idle
    }

    private static func message(for error: Error) -> String {
        if case KantataAPIError.unauthorized = error {
            return "Your Kantata connection needs to be reconnected."
        }
        if case SyncError.partialFailure(let items) = error {
            return "Couldn't sync: \(items.joined(separator: ", "))."
        }
        return "Couldn't reach Kantata. Check your connection and try again."
    }
}
