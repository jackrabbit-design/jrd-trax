import Foundation

enum RunningTimerLogic {
    static func elapsedMinutes(from startedAt: Date, to now: Date) -> Int {
        Int((now.timeIntervalSince(startedAt) / 60).rounded())
    }
}
