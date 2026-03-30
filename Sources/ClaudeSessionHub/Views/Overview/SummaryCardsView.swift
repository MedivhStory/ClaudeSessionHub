import SwiftUI

struct SummaryCardsView: View {
    let attentionCount: Int
    let activeCount: Int
    let projectCount: Int
    let lastScanTime: Date?

    var body: some View {
        HStack(spacing: 12) {
            card(
                value: "\(attentionCount)",
                label: "Attention",
                color: .orange,
                icon: "exclamationmark.triangle.fill"
            )
            .accessibilityIdentifier("summaryAttention")
            card(
                value: "\(activeCount)",
                label: "Active",
                color: .green,
                icon: "bolt.fill"
            )
            .accessibilityIdentifier("summaryActive")
            card(
                value: "\(projectCount)",
                label: "Projects",
                color: .purple,
                icon: "folder.fill"
            )
            .accessibilityIdentifier("summaryProjects")
            card(
                value: scanTimeText,
                label: "Last Scan",
                color: .gray,
                icon: "clock"
            )
            .accessibilityIdentifier("summaryLastScan")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var scanTimeText: String {
        guard let time = lastScanTime else { return "--" }
        let seconds = Int(-time.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    private func card(value: String, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
