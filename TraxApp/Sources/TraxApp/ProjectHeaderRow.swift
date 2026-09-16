import SwiftUI
import AppKit
import TraxKit

struct ProjectHeaderRow: View {
    let project: Project
    let scheduledMinutes: Int
    let loggedMinutes: Int

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: project.colorHex))
                .frame(width: 10, height: 10)
            Button {
                NSWorkspace.shared.open(project.workspaceURL)
            } label: {
                HStack(spacing: 4) {
                    Text(project.name)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            Spacer()
            Text("\(DurationFormatting.short(loggedMinutes)) logged of \(DurationFormatting.short(scheduledMinutes)) scheduled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.headline)
    }
}
