import Foundation
import TraxKit

enum TaskSorting {
    static func sorted(_ tasks: [TraxTask]) -> [TraxTask] {
        tasks.sorted { lhs, rhs in
            let lhsRank = priorityRank(lhs.priority)
            let rhsRank = priorityRank(rhs.priority)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return dueDateSortsBefore(lhs.dueDate, rhs.dueDate)
        }
    }

    private static func priorityRank(_ priority: Priority) -> Int {
        Priority.allCases.firstIndex(of: priority) ?? Priority.allCases.count
    }

    private static func dueDateSortsBefore(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l < r
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        }
    }
}
