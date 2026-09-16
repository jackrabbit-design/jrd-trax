import SwiftUI
import TraxKit

struct TodayView: View {
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var toolbar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Text(dateLabel)
                        .font(.headline)
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                Spacer()
                Button {
                    // Sync is wired up in a future sub-project.
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(true)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Text("Last synced —")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
}

#Preview {
    TodayView()
}
