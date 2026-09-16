import Foundation
import SwiftUI

enum DurationFormatting {
    static func short(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }
}

enum DueDateFormatting {
    static func short(_ date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue = calendar.startOfDay(for: date)
        let daysDifference = calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0

        if daysDifference == 0 { return "Today" }
        if daysDifference > 6 { return "Next wk" }
        return startOfDue.formatted(.dateTime.weekday(.abbreviated))
    }
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
