import Testing
import Foundation
@testable import TraxApp

@Suite("Running timer logic")
struct RunningTimerLogicTests {
    @Test("rounds up at 30 seconds or more")
    func roundsUpAtHalfMinute() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(90) // 1.5 minutes
        #expect(RunningTimerLogic.elapsedMinutes(from: start, to: now) == 2)
    }

    @Test("rounds down under 30 seconds")
    func roundsDownUnderHalfMinute() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(29)
        #expect(RunningTimerLogic.elapsedMinutes(from: start, to: now) == 0)
    }

    @Test("zero elapsed time is zero minutes")
    func zeroElapsed() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(RunningTimerLogic.elapsedMinutes(from: start, to: start) == 0)
    }
}
