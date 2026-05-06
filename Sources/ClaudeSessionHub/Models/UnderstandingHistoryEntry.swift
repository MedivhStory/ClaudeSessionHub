import Foundation

/// Chronologically-sortable entry for the per-field history drawer.
///
/// Three cases cover the v0.2.9 storage model:
/// - `.artifact` — a versioned title/progress/summary value with provenance
///   (carries an `isCurrent` flag set when this artifact is the resolved
///   current value for its field).
/// - `.selection` — a `SelectionEvent` recording an explicit user adoption,
///   placed in the timeline for context (no value of its own).
/// - `.legacy` — Pre-v0.2.9 baseline read via `LegacyUnderstandingAdapter`
///   (carries an `isCurrent` flag set when no V2 artifact owns this field
///   and legacy still has a value to display).
public enum HistoryEntry: Sendable, Equatable {
    case artifact(UnderstandingArtifact, isCurrent: Bool)
    case selection(SelectionEvent)
    case legacy(LegacyUnderstandingSnapshot, field: UnderstandingField, isCurrent: Bool)

    /// Sort key for chronological ordering. Legacy entries with a nil
    /// `generatedAt` fall back to `.distantPast` so they sort to the
    /// chronological start regardless of artifact timestamps.
    public var timestamp: Date {
        switch self {
        case .artifact(let artifact, _):
            return artifact.createdAt
        case .selection(let event):
            return event.timestamp
        case .legacy(let snapshot, _, _):
            return snapshot.generatedAt ?? .distantPast
        }
    }

    /// Case-rank tiebreaker for entries at the same `timestamp`. Legacy
    /// rows sort first (baseline / oldest), artifacts next, selection
    /// events last. Used after `timestamp` so the history drawer renders
    /// a deterministic order when synthetic / coarse timestamps collide.
    public var caseOrder: Int {
        switch self {
        case .legacy:    return 0
        case .artifact:  return 1
        case .selection: return 2
        }
    }

    /// Final tiebreaker after `timestamp` and `caseOrder`. Uses the
    /// artifact / selection UUID so two entries of the same case at the
    /// same timestamp still order deterministically. Legacy returns ""
    /// because at most one legacy entry exists per (session, field).
    public var stableID: String {
        switch self {
        case .legacy:                return ""
        case .artifact(let art, _):  return art.id.uuidString
        case .selection(let event):  return event.id.uuidString
        }
    }
}
