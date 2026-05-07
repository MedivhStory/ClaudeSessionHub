import SwiftUI

/// Read-only structural evidence panel rendered below `LLMPanelView` in
/// the expanded session tile (v0.2.9 P4 C3, per PLAN-v0.2.9.md §9
/// "rendered below the AI panel, expandable").
///
/// Reads from `SessionStore.evidence(for:)` — pure rule, no LLM call,
/// no async. Empty packages render nothing (no header row, no chrome)
/// so unknown sessions / brand-new sessions don't show an empty section.
/// Collapsed by default so the section doesn't compete with the primary
/// AI understanding panel above it.
struct EvidencePanel: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary

    @State private var isExpanded = false

    private var package: EvidencePackage {
        store.evidence(for: session.ref)
    }

    var body: some View {
        if package.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(package.items, id: \.category) { item in
                        evidenceRow(item)
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 8)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11))
                    Text("证据")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            }
            .accessibilityIdentifier("evidencePanel_\(session.ref.sessionID)")
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func evidenceRow(_ item: EvidenceItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(item.lines.indices, id: \.self) { idx in
                Text(item.lines[idx])
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("evidence_\(item.category.rawValue)_\(session.ref.sessionID)")
        .accessibilityElement(children: .combine)
    }
}
