import SwiftUI
import SwiftData
import Combine
import TraxKit
import KantataAPI

struct TodayView: View {
    let apiClient: KantataAPIClient

    @Environment(\.modelContext) private var modelContext
    @Query private var syncStates: [SyncState]
    @State private var syncController: SyncController?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var now: Date = .now
    private let clockTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var lastSyncedAt: Date? {
        syncStates.first?.lastSyncedAt
    }

    private var lastSyncedLabel: String {
        guard let lastSyncedAt else { return "Never synced" }
        return "Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))"
    }

    private var isStale: Bool {
        guard let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) > 10 * 3600
    }

    private var staleBannerText: String {
        guard let lastSyncedAt else { return "You haven't synced yet. Your schedule may be out of date." }
        let hours = Int(now.timeIntervalSince(lastSyncedAt) / 3600)
        return "\(hours) hours since last sync. Your schedule may be out of date."
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if isStale {
                staleBanner
            }
            Divider()
            RunningTimerBanner()
            TaskListView(selectedDate: selectedDate)
            Divider()
            AddTimeRow(date: selectedDate)
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if syncController == nil {
                syncController = SyncController(engine: SyncEngine(modelContext: modelContext, apiClient: apiClient))
            }
        }
        .onReceive(clockTicker) { now = $0 }
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
                    Task { await syncController?.startSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(syncController == nil)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Text(lastSyncedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private var staleBanner: some View {
        HStack {
            Text(staleBannerText)
                .font(.caption)
            Spacer()
            Button("Sync now") {
                Task { await syncController?.startSync() }
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.2))
    }
}

#Preview {
    TodayView(apiClient: KantataAPIClient(transport: URLSessionHTTPTransport(), tokenProvider: { nil }))
}
