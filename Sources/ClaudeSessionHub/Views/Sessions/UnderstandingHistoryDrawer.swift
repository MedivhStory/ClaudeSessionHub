import SwiftUI

/// Read-only per-field history viewer (v0.2.9 P3 C3).
///
/// Presents the chronological list returned by
/// `SessionStore.fieldHistory(for:field:)`. No editing, no adoption,
/// no regenerate — those flows live on the panel row, not in the drawer.
///
/// Layout:
/// - Header: field name + close button.
/// - Body: chronological scroll of artifact / selection / legacy rows.
///   Each row that represents the resolved current value carries a "当前"
///   tag. Legacy rows carry an explicit "Pre-v0.2.9 baseline" label.
struct UnderstandingHistoryDrawer: View {
    @Environment(SessionStore.self) var store
    @Environment(\.dismiss) private var dismiss
    let session: SessionSummary
    let field: UnderstandingField

    private var entries: [HistoryEntry] {
        store.fieldHistory(for: session.ref, field: field)
    }

    private var heading: String {
        switch field {
        case .title:    return "标题 历史"
        case .progress: return "进展 历史"
        case .summary:  return "摘要 历史"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(heading)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            entryRow(entry)
                            if index < entries.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 260, idealHeight: 360, maxHeight: 520)
        .accessibilityIdentifier("historyDrawer_\(field.rawValue)_\(session.ref.sessionID)")
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        Text("暂无历史记录")
            .font(.system(size: 12))
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
            .accessibilityIdentifier("historyDrawerEmpty_\(field.rawValue)_\(session.ref.sessionID)")
    }

    @ViewBuilder
    private func entryRow(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .artifact(let artifact, let isCurrent):
            artifactRow(artifact, isCurrent: isCurrent)
        case .selection(let event):
            selectionRow(event)
        case .legacy(let snapshot, let entryField, let isCurrent):
            legacyRow(snapshot, field: entryField, isCurrent: isCurrent)
        }
    }

    private func artifactRow(_ artifact: UnderstandingArtifact, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SourceChip(source: chipSource(for: artifact.source))
                Text(artifact.createdAt.relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                if isCurrent {
                    currentTag
                }
                Spacer(minLength: 0)
            }
            Text(artifact.value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectionRow(_ event: SelectionEvent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
            Text(selectionLabel(event.action))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(event.timestamp.relativeFormatted)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private func legacyRow(
        _ snapshot: LegacyUnderstandingSnapshot,
        field rowField: UnderstandingField,
        isCurrent: Bool
    ) -> some View {
        let value: String? = {
            switch rowField {
            case .title:    return snapshot.title
            case .progress: return snapshot.progress
            case .summary:  return snapshot.summary
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SourceChip(source: .legacy)
                Text("Pre-v0.2.9 baseline")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.orange)
                if let when = snapshot.generatedAt {
                    Text(when.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if isCurrent {
                    currentTag
                }
                Spacer(minLength: 0)
            }
            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("historyLegacyRow_\(rowField.rawValue)_\(session.ref.sessionID)")
    }

    private var currentTag: some View {
        Text("当前")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.green.opacity(0.15))
            .foregroundStyle(.green)
            .clipShape(.capsule)
            .accessibilityLabel("当前显示版本")
    }

    private func chipSource(for source: UnderstandingSource) -> ResolvedSource {
        switch source {
        case .ai:     return .ai
        case .manual: return .manual
        case .rule:   return .rule
        }
    }

    private func selectionLabel(_ action: SelectionAction) -> String {
        switch action {
        case .adopt: return "采用了一个版本"
        }
    }
}
