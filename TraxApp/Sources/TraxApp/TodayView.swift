import SwiftUI
import TraxKit

struct TodayView: View {
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    private var relativeDate: String {
        let now = Calendar.current.startOfDay(for: .now)
        let components = Calendar.current.dateComponents([.day], from: now, to: selectedDate)
        switch components.day {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case -1:
            return "Yesterday"
        default:
            guard let day = components.day else { return "" }
            return day > 0 ? "+\(day) days" : "\(day) days"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
            Divider()
            AddTimeRow(date: selectedDate)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var toolbar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                HStack(spacing: 16) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    VStack(spacing:2) {
                        Text(dateLabel)
                            .font(.headline)
                            .frame(minWidth:85)
                        Text(relativeDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                Spacer()
                Text("Last synced —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    // Sync is wired up in a future sub-project.
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(true)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
    }
}

#Preview {
    TodayView()
}
