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
}
