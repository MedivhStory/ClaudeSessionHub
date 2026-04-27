import Foundation

/// Per-session container for v0.2.9 versioned understanding artifacts,
/// current pointers, selection events, optional rationale, and an
/// optional legacy snapshot derived from V1 storage at read time.
public struct UnderstandingState: Sendable, Equatable, Identifiable {
    public let sessionID: String

    public var titleVersions: [UnderstandingArtifact]
    public var currentTitleVersionID: UUID?

    public var progressVersions: [UnderstandingArtifact]
    public var currentProgressVersionID: UUID?

    public var summaryVersions: [UnderstandingArtifact]
    public var currentSummaryVersionID: UUID?

    public var selectionEvents: [SelectionEvent]
    public var currentRationale: RationaleMetadata?

    /// Read from `understanding.json` via LegacyUnderstandingAdapter at
    /// state-load time. Not persisted in `understanding-v2.json`.
    public var legacySnapshot: LegacyUnderstandingSnapshot?

    public var id: String { sessionID }

    public init(
        sessionID: String,
        titleVersions: [UnderstandingArtifact] = [],
        currentTitleVersionID: UUID? = nil,
        progressVersions: [UnderstandingArtifact] = [],
        currentProgressVersionID: UUID? = nil,
        summaryVersions: [UnderstandingArtifact] = [],
        currentSummaryVersionID: UUID? = nil,
        selectionEvents: [SelectionEvent] = [],
        currentRationale: RationaleMetadata? = nil,
        legacySnapshot: LegacyUnderstandingSnapshot? = nil
    ) {
        self.sessionID = sessionID
        self.titleVersions = titleVersions
        self.currentTitleVersionID = currentTitleVersionID
        self.progressVersions = progressVersions
        self.currentProgressVersionID = currentProgressVersionID
        self.summaryVersions = summaryVersions
        self.currentSummaryVersionID = currentSummaryVersionID
        self.selectionEvents = selectionEvents
        self.currentRationale = currentRationale
        self.legacySnapshot = legacySnapshot
    }
}
