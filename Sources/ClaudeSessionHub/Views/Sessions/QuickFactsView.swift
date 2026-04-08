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
                // Files + next step (stats/context moved to collapsed tile)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        recentFilesCard
                        nextStepCard
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let files = detail?.recentFiles, !files.isEmpty {
                ForEach(files.suffix(5), id: \.self) { file in
                    Text((file as NSString).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text("\(session.filesTouched) files touched")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // contextUsageCard and sessionStatsCard removed — moved to collapsed tile right side

    @ViewBuilder
    private var nextStepCard: some View {
        if let nextStep = detail?.nextStep {
            VStack(alignment: .leading, spacing: 4) {
                Label("下一步", systemImage: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nextStep)
                    .font(.system(size: 11))
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
