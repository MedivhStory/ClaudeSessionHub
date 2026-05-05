import SwiftUI

/// Right-side AI understanding panel shown in expanded session tile.
///
/// v0.2.9 P2 C3 additions:
/// - Inline `TextField` for title and progress with focus / commit / cancel.
/// - Per-field regenerate icon buttons (calls SessionStore.regenerate*).
/// - "Adopt AI version" pill that appears only when a manual current
///   exists alongside an unadopted AI candidate.
/// - Existing full-regenerate button (`enhanceWithLLM`) stays.
///
/// All buttons go through C1/C2 SessionStore APIs only — no new flow
/// logic is added here.
struct LLMPanelView: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary

    // Edit state
    @State private var titleBuffer: String = ""
    @State private var progressBuffer: String = ""
    @FocusState private var focusedField: UnderstandingField?

    // MARK: - Resolved fields

    private var titleField: ResolvedField {
        store.resolvedTitle(for: session.ref)
    }

    private var progressField: ResolvedField {
        store.resolvedProgress(for: session.ref)
    }

    private var summaryField: ResolvedField {
        store.resolvedSummary(for: session.ref)
    }

    private var hasUnderstandingContent: Bool {
        let sources: [ResolvedSource] = [titleField.source, progressField.source, summaryField.source]
        return sources.contains(where: { $0 == .ai || $0 == .manual || $0 == .legacy })
    }

    private var hasLegacyCurrent: Bool {
        titleField.source == .legacy
            || progressField.source == .legacy
            || summaryField.source == .legacy
    }

    private var isConfigured: Bool {
        store.settings.llmConfig.isConfigured
    }

    private var metadata: ResolvedMetadata? {
        store.resolvedMetadata(for: session.ref)
    }

    // MARK: - Body

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
        titleRow
        progressRow
        summaryRow

        if hasLegacyCurrent {
            Text("Pre-v0.2.9 baseline · 重新生成可创建带追溯信息的 AI 版本")
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(.orange)
                .accessibilityIdentifier("legacyBaselineHint_\(session.ref.sessionID)")
        }

        bottomRow
    }

    // MARK: - Per-field rows

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("AI 标题:")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("", text: $titleBuffer, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(1...2)
                .focused($focusedField, equals: .title)
                .onSubmit { commitEdit(.title) }
                .onExitCommand { cancelEdit(.title) }
                .onChange(of: titleField.value, initial: true) { _, newValue in
                    if focusedField != .title {
                        titleBuffer = newValue ?? ""
                    }
                }
                .accessibilityIdentifier("titleEdit_\(session.ref.sessionID)")
                .accessibilityLabel("编辑标题")

            SourceChip(source: titleField.source)
            regenerateButton(for: .title)
            adoptButtonIfNeeded(for: .title)
        }
    }

    private var progressRow: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("AI 进展:")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("", text: $progressBuffer, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(1...2)
                .focused($focusedField, equals: .progress)
                .onSubmit { commitEdit(.progress) }
                .onExitCommand { cancelEdit(.progress) }
                .onChange(of: progressField.value, initial: true) { _, newValue in
                    if focusedField != .progress {
                        progressBuffer = newValue ?? ""
                    }
                }
                .accessibilityIdentifier("progressEdit_\(session.ref.sessionID)")
                .accessibilityLabel("编辑进展")

            SourceChip(source: progressField.source)
            regenerateButton(for: .progress)
            adoptButtonIfNeeded(for: .progress)
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        if let summary = summaryField.value, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("AI 摘要:")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    SourceChip(source: summaryField.source)
                    regenerateButton(for: .summary)
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        } else if isConfigured {
            // No summary yet — offer regenerate so users can produce one
            // without going through the full enhance button.
            HStack(spacing: 4) {
                Text("AI 摘要:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("(未生成)")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.tertiary)
                regenerateButton(for: .summary)
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if let meta = metadata {
                Text(meta.model)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("·").foregroundStyle(.quaternary)
                Text(meta.time.relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                if meta.isStale {
                    Text("·").foregroundStyle(.quaternary)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("已过期")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("staleMarker_\(session.ref.sessionID)")
                }
            }

            if isConfigured {
                Button {
                    Task { try? await store.enhanceWithLLM(for: session.ref) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                        Text("全部重新生成")
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

    // MARK: - Per-field action buttons

    @ViewBuilder
    private func regenerateButton(for field: UnderstandingField) -> some View {
        if isConfigured {
            Button {
                Task {
                    switch field {
                    case .title:    try? await store.regenerateTitle(for: session.ref)
                    case .progress: try? await store.regenerateProgress(for: session.ref)
                    case .summary:  try? await store.regenerateSummary(for: session.ref)
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.purple)
            .help(regenerateHelp(field))
            .accessibilityIdentifier("regenerate\(fieldName(field))_\(session.ref.sessionID)")
            .accessibilityLabel(regenerateHelp(field))
        }
    }

    @ViewBuilder
    private func adoptButtonIfNeeded(for field: UnderstandingField) -> some View {
        if let candidate = store.unadoptedAICandidate(for: session.ref, field: field) {
            Button {
                try? store.adoptAIVersion(
                    for: session.ref,
                    field: field,
                    versionID: candidate.id
                )
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                    Text("采用 AI 版本")
                }
                .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.purple)
            .controlSize(.mini)
            .help("AI 候选版本已生成,点击采用并替换当前手动值")
            .accessibilityIdentifier("adoptAI\(fieldName(field))_\(session.ref.sessionID)")
            .accessibilityLabel("采用 AI 版本 \(fieldLabel(field))")
        }
    }

    // MARK: - Edit commit / cancel

    private func commitEdit(_ field: UnderstandingField) {
        let buffer = field == .title ? titleBuffer : progressBuffer
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (field == .title ? titleField.value : progressField.value) ?? ""

        if !trimmed.isEmpty && trimmed != current {
            switch field {
            case .title:    store.editTitle(for: session.ref, newValue: trimmed)
            case .progress: store.editProgress(for: session.ref, newValue: trimmed)
            case .summary:  break // no-op; summary has no manual edit path
            }
        } else if trimmed.isEmpty {
            // Empty submit reverts to current value rather than wiping.
            switch field {
            case .title:    titleBuffer = current
            case .progress: progressBuffer = current
            case .summary:  break
            }
        }
        focusedField = nil
    }

    private func cancelEdit(_ field: UnderstandingField) {
        switch field {
        case .title:    titleBuffer = titleField.value ?? ""
        case .progress: progressBuffer = progressField.value ?? ""
        case .summary:  break
        }
        focusedField = nil
    }

    // MARK: - Empty / unconfigured state

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

    // MARK: - Field labels

    private func fieldName(_ field: UnderstandingField) -> String {
        switch field {
        case .title:    return "Title"
        case .progress: return "Progress"
        case .summary:  return "Summary"
        }
    }

    private func fieldLabel(_ field: UnderstandingField) -> String {
        switch field {
        case .title:    return "标题"
        case .progress: return "进展"
        case .summary:  return "摘要"
        }
    }

    private func regenerateHelp(_ field: UnderstandingField) -> String {
        "重新生成 \(fieldLabel(field))"
    }
}
