import SwiftUI

struct QuickFactsView: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(.top, 4)
    }

    // MARK: - Cards

    private var recentFilesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Recent Files", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(session.filesTouched) files touched")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contextUsageCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Context", systemImage: "chart.bar")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let usage = session.contextUsage {
                let usedK = usage.promptContext / 1000
                let limitK = usage.limit / 1000
                ProgressView(value: usage.percentage)
                    .tint(contextBarColor(usage.percentage))
                Text("\u{4E0A}\u{4E0B}\u{6587}\u{5360}\u{7528} \(usedK)k / \(limitK > 0 ? "\(limitK / 1000)M" : "?")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("N/A")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next Step", systemImage: "arrow.right.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("--")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionStatsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Stats", systemImage: "chart.xyaxis.line")
                .font(.caption)
                .foregroundStyle(.secondary)

            let dateStr = session.createdAt.formatted(date: .abbreviated, time: .omitted)
            Text("\u{521B}\u{5EFA} \(dateStr) \u{00B7} \(session.turnCount) turns")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: 12) {
            if session.runtimeState == .stopped {
                actionButton("Resume", icon: "play.fill", color: .blue) {
                    let target = ResumeTarget(
                        executable: "claude",
                        arguments: ["--resume", session.ref.sessionID],
                        workingDirectory: session.cwd,
                        displayCommand: "claude --resume \(session.ref.sessionID)"
                    )
                    TerminalLauncher.launch(target: target, in: .ghostty)
                }
            }

            actionButton("Copy Command", icon: "doc.on.doc", color: .secondary) {
                let target = ResumeTarget(
                    executable: "claude",
                    arguments: ["--resume", session.ref.sessionID],
                    workingDirectory: session.cwd,
                    displayCommand: "claude --resume \(session.ref.sessionID)"
                )
                let cmd = TerminalLauncher.copyCommand(for: target)
                TerminalLauncher.copyToClipboard(cmd)
            }

            if let cwd = session.cwd {
                actionButton("Open in Finder", icon: "folder", color: .secondary) {
                    #if canImport(AppKit)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                    #endif
                }
            }

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
}
