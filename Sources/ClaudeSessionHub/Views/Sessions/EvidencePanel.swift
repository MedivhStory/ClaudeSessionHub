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
        Self.expandedTileFiltered(store.evidence(for: session.ref))
    }

    /// View-level display policy for the expanded-tile host context.
    /// Drops categories whose information is already surfaced at higher
    /// fidelity elsewhere in the same expanded tile:
    ///
    /// - `.recentFiles` — `QuickFactsView` shows concrete file names;
    ///   the composer's degraded `filesTouched` count is lower fidelity.
    /// - `.timeAnchors` — the tile header already shows created /
    ///   last-active timestamps.
    /// - `.branchCwd` / `.projectName` — the tile metadata row already
    ///   shows project name + branch.
    /// - `.relatedSessions` — the left column already lists related
    ///   sessions with type chips.
    ///
    /// Keeps `.currentPhase` and `.latestProgress` — neither is
    /// duplicated by other expanded-tile chrome.
    ///
    /// The composer's canonical package is unchanged; this filter is a
    /// **host-context** policy, not a model change. Different host views
    /// (a future session inspector / detail pane) may apply a different
    /// filter or none at all.
    static func expandedTileFiltered(_ package: EvidencePackage) -> EvidencePackage {
        let dropped: Set<EvidenceCategory> = [
            .recentFiles,
            .timeAnchors,
            .branchCwd,
            .projectName,
            .relatedSessions
        ]
        let kept = package.items.filter { !dropped.contains($0.category) }
        return EvidencePackage(items: kept)
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
