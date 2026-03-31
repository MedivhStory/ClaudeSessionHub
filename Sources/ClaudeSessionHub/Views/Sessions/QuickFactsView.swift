import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct QuickFactsView: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary
    @State private var detail: SessionDetail?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // 2x2 grid
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        recentFilesCard
                        contextUsageCard
                    }
                    GridRow {
                        nextStepCard
                        sessionStatsCard
                    }
                }

                // Actions row
                actionsRow
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickFacts_\(session.ref.sessionID)")
        .task {
            detail = await store.loadDetail(for: session.ref)
            isLoading = false
        }
    }

    // MARK: - Cards

    private var recentFilesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("最近改动", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let files = detail?.recentFiles, !files.isEmpty {
                ForEach(files.suffix(5), id: \.self) { file in
                    Text((file as NSString).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text("\(session.filesTouched) files touched")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spec: no high-confidence data → hide from tile signals. In Quick Facts only,
    /// show estimated value with ~ prefix if cumulativeTokens available, else hide entirely.
    @ViewBuilder
    private var contextUsageCard: some View {
        if let usage = session.contextUsage {
            // High-confidence: show progress bar + exact value
            VStack(alignment: .leading, spacing: 4) {
                Label("上下文占用", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let usedK = usage.promptContext / 1000
                let limitM = usage.limit / 1_000_000
                ProgressView(value: usage.percentage)
                    .tint(contextBarColor(usage.percentage))
                Text("\(usedK)k / \(limitM > 0 ? "\(limitM)M" : "\(usage.limit / 1000)k")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quickFactsContext_\(session.ref.sessionID)")
        } else {
            // No high-confidence usage data — hide entirely.
            // Cumulative tokens ≠ current context window, so no estimation shown.
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    /// Only shown when nextStep is non-nil (spec: "nextStep = nil → hide row")
    @ViewBuilder
    private var nextStepCard: some View {
        if let nextStep = detail?.nextStep {
            VStack(alignment: .leading, spacing: 4) {
                Label("下一步", systemImage: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nextStep)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("quickFactsNextStep_\(session.ref.sessionID)")
        } else {
            // Empty cell to maintain grid layout, but no visible content
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    private var sessionStatsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("统计", systemImage: "chart.xyaxis.line")
                .font(.caption)
                .foregroundStyle(.secondary)

            let dateStr = session.createdAt.formatted(date: .abbreviated, time: .omitted)
            Text("创建 \(dateStr) · \(session.turnCount) turns")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let tokens = detail?.cumulativeTokens {
                Text("累计消耗 \(formatTokenCount(tokens.totalTokens)) tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Show both recent and total errors so users can distinguish active warnings from history
            if session.recentErrorCount > 0 || (detail?.totalErrorCount ?? 0) > 0 {
                let recentStr = "近期 \(session.recentErrorCount) errors"
                let totalStr = detail.map { "总计 \($0.totalErrorCount)" } ?? ""
                Text("\(recentStr)\(totalStr.isEmpty ? "" : " · \(totalStr)")")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickFactsStats_\(session.ref.sessionID)")
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: 12) {
            actionButton("Resume", icon: "play.fill", color: .blue) {
                Task {
                    if let target = await store.makeResumeTarget(for: session.ref) {
                        TerminalLauncher.launch(target: target, in: store.selectedTerminal)
                    }
                }
            }

            actionButton("Copy Command", icon: "doc.on.doc", color: .secondary) {
                Task {
                    if let target = await store.makeResumeTarget(for: session.ref) {
                        let cmd = TerminalLauncher.copyCommand(for: target)
                        TerminalLauncher.copyToClipboard(cmd)
                    }
                }
            }

            if let cwd = session.cwd {
                actionButton("Open in Finder", icon: "folder", color: .secondary) {
                    #if canImport(AppKit)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                    #endif
                }
            }

            let isArchived = store.archiveStore.isArchived(session.ref)
            actionButton(isArchived ? "Unarchive" : "Archive",
                         icon: isArchived ? "tray.and.arrow.up" : "archivebox",
                         color: .secondary) {
                if isArchived {
                    store.archiveStore.unarchive(session.ref)
                } else {
                    store.archiveStore.archive(session.ref)
                }
            }
            .accessibilityIdentifier("archiveButton_\(session.ref.sessionID)")

            Spacer()
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func contextBarColor(_ percentage: Double) -> Color {
        if percentage >= 0.9 { return .red }
        if percentage >= 0.75 { return .orange }
        return .green
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }
}
