import Foundation

/// Read-only structural evidence categories surfaced in the v0.2.9 P4
/// evidence panel below the AI understanding section.
///
/// Cases align with PLAN-v0.2.9.md §9 **minus** `recentToolOps`, which is
/// omitted from P4 because it has no sync read path on `main` and rev.3
/// forbids new caches/scanners. See `docs/PLAN-v0.2.9-P4.md` C0 audit
/// row 2 for the full audit decision; PM ratified the omission.
public enum EvidenceCategory: String, Sendable, Equatable, CaseIterable {
    case recentFiles
    case timeAnchors
    case branchCwd
    case relatedSessions
    case projectName
    case currentPhase
    case latestProgress
}

/// One rendered evidence row. `lines` is non-empty in any value emitted
/// by `EvidenceComposer.compose(...)`; empty-line categories are pruned
/// at composition time so consumers never need to render an empty row.
public struct EvidenceItem: Sendable, Equatable {
    public let category: EvidenceCategory
    public let title: String
    public let lines: [String]

    public init(category: EvidenceCategory, title: String, lines: [String]) {
        self.category = category
        self.title = title
        self.lines = lines
    }
}

/// Ordered collection of evidence items for one session. Items appear in
/// PLAN §9 listing order (minus the omitted `recentToolOps`); empty
/// categories are dropped at composition time.
public struct EvidencePackage: Sendable, Equatable {
    public let items: [EvidenceItem]

    public init(items: [EvidenceItem] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
}
