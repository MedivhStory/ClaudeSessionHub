import SwiftUI

/// Right-side AI understanding panel shown in expanded session tile.
/// Has 4 states: fresh snapshot, stale snapshot, no snapshot (configured), no snapshot (unconfigured).
struct LLMPanelView: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary

    private var snapshot: LLMUnderstandingSnapshot? {
        store.understandingStore.snapshot(for: session.ref.sessionID)
    }

    private var isStale: Bool {
        store.understandingStore.isStale(for: session.ref.sessionID, lastActiveAt: session.lastActiveAt)
    }

    private var isConfigured: Bool {
        store.settings.llmConfig.isConfigured
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 理解", systemImage: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.purple)

            if let snap = snapshot {
                snapshotContent(snap)
            } else if isConfigured {
                noSnapshotConfigured
            } else {
                noSnapshotUnconfigured
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("llmPanel_\(session.ref.sessionID)")
        .accessibilityElement(children: .contain)
    }

    // MARK: - State 1 & 2: Has snapshot

    @ViewBuilder
    private func snapshotContent(_ snap: LLMUnderstandingSnapshot) -> some View {
        // AI title
        HStack(spacing: 4) {
            Text("AI 标题:")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(snap.title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }

        // AI progress
        if let progress = snap.progress {
            HStack(spacing: 4) {
                Text("AI 进展:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(progress)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }

        // AI summary
        if let summary = snap.summary {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 摘要:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        }

        // Bottom line: model · time · [stale warning] · [regenerate button]
        HStack(spacing: 6) {
            Text(snap.modelName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text("·").foregroundStyle(.quaternary)
            Text(snap.generatedAt.relativeFormatted)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            if isStale {
                Text("·").foregroundStyle(.quaternary)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("已过期")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if isConfigured {
                Button {
                    Task { try? await store.enhanceWithLLM(for: session.ref) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                        Text("重新生成")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                .controlSize(.mini)
                .accessibilityIdentifier("regenerateAI_\(session.ref.sessionID)")
                .accessibilityLabel("重新生成 AI 理解")
            }
        }
    }

    // MARK: - State 3: No snapshot, LLM configured

    private var noSnapshotConfigured: some View {
        Button {
            Task { try? await store.enhanceWithLLM(for: session.ref) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("生成 AI 理解")
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("generateAI_\(session.ref.sessionID)")
        .accessibilityLabel("生成 AI 理解")
    }

    // MARK: - State 4: No snapshot, LLM not configured

    private var noSnapshotUnconfigured: some View {
        Text("配置 AI 增强以获取更好的理解")
            .font(.system(size: 11))
            .italic()
            .foregroundStyle(.tertiary)
    }

    // MARK: - Helpers

    // relativeTime moved to Date.relativeFormatted extension
}
