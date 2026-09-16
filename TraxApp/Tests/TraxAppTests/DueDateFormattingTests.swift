import Testing
import Foundation
@testable import TraxApp

@Suite("Due date formatting")
struct DueDateFormattingTests {
    private var today: Date { Calendar.current.startOfDay(for: .now) }

    @Test("today formats as 'Today'")
    func formatsToday() {
        #expect(DueDateFormatting.short(today, relativeTo: today) == "Today")
    }

    @Test("within the next 6 days formats as the abbreviated weekday")
    func formatsWithinWeek() {
        let inThreeDays = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        let expectedWeekday = inThreeDays.formatted(.dateTime.weekday(.abbreviated))
        #expect(DueDateFormatting.short(inThreeDays, relativeTo: today) == expectedWeekday)
    }

    @Test("more than 6 days out formats as 'Next wk'")
    func formatsNextWeek() {
        let inTenDays = Calendar.current.date(byAdding: .day, value: 10, to: today)!
        #expect(DueDateFormatting.short(inTenDays, relativeTo: today) == "Next wk")
    }
}
