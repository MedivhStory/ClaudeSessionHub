import SwiftUI

/// Right-side AI understanding panel shown in expanded session tile.
/// In v0.2.9 P1 the panel reads through `SessionStore.resolved*` so the
/// rendered values + source chips reflect the v0.2.9 display policy
/// (Manual > AI > Legacy > Rule). Layout intentionally mirrors the
/// v0.2.8 panel; only chip labels and the legacy baseline indicator are
/// new in P1.
struct LLMPanelView: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary

    private var titleField: ResolvedField {
        store.resolvedTitle(for: session.ref)
    }

    private var progressField: ResolvedField {
        store.resolvedProgress(for: session.ref)
    }

    private var summaryField: ResolvedField {
        store.resolvedSummary(for: session.ref)
    }

    /// True when at least one current field comes from a v2 AI artifact
    /// or a legacy baseline. Used to decide between the values panel and
    /// the "generate AI" call-to-action.
    private var hasUnderstandingContent: Bool {
        let sources: [ResolvedSource] = [titleField.source, progressField.source, summaryField.source]
        return sources.contains(where: { $0 == .ai || $0 == .manual || $0 == .legacy })
    }

    /// True when any displayed field's current value comes from the
    /// pre-v0.2.9 legacy snapshot. Drives the "Pre-v0.2.9 baseline" hint
    /// and the regenerate-to-create-AI affordance.
    private var hasLegacyCurrent: Bool {
        titleField.source == .legacy
            || progressField.source == .legacy
            || summaryField.source == .legacy
    }

    private var isConfigured: Bool {
        store.settings.llmConfig.isConfigured
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 理解", systemImage: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.purple)
                .accessibilityAddTraits(.isHeader)

            if hasUnderstandingContent {
                resolvedContent
            } else if isConfigured {
                noContentConfigured
            } else {
                noContentUnconfigured
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("llmPanel_\(session.ref.sessionID)")
        .accessibilityElement(children: .contain)
    }

    // MARK: - Has resolved content

    @ViewBuilder
    private var resolvedContent: some View {
        // Title
        HStack(alignment: .top, spacing: 4) {
            Text("AI 标题:")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if let value = titleField.value {
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            SourceChip(source: titleField.source)
        }

        // Progress
        if let progress = progressField.value, !progress.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                Text("AI 进展:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(progress)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                SourceChip(source: progressField.source)
            }
        }

        // Summary
        if let summary = summaryField.value, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("AI 摘要:")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    SourceChip(source: summaryField.source)
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        }

        // Legacy baseline note when any current field is legacy.
        if hasLegacyCurrent {
            Text("Pre-v0.2.9 baseline · 重新生成可创建带追溯信息的 AI 版本")
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(.orange)
                .accessibilityIdentifier("legacyBaselineHint_\(session.ref.sessionID)")
        }

        // Bottom action row.
        HStack(spacing: 6) {
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

    // MARK: - No understanding content yet

    private var noContentConfigured: some View {
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

    private var noContentUnconfigured: some View {
        Text("配置 AI 增强以获取更好的理解")
            .font(.system(size: 11))
            .italic()
            .foregroundStyle(.tertiary)
    }
}
