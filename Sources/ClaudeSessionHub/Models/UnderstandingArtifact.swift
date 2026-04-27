import Foundation

// MARK: - Source / Trigger / Stale

public enum UnderstandingSource: String, Sendable, Equatable, CaseIterable {
    case rule
    case ai
    case manual
}

public enum UnderstandingTrigger: String, Sendable, Equatable, CaseIterable {
    case scan
    case manualGenerate
    case manualEdit
}

public enum StaleState: Sendable, Equatable {
    case fresh
    case staleSessionUpdated(at: Date)
    case stalePartial(reason: String)
    case legacyUnknown
}

// MARK: - UnderstandingArtifact

/// A single versioned title / progress / summary value with provenance metadata.
public struct UnderstandingArtifact: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let value: String
    public let source: UnderstandingSource
    public let trigger: UnderstandingTrigger
    public let createdAt: Date
    /// Hash of session state at generation. Required for `.ai` and `.rule`
    /// artifacts; optional for `.manual` artifacts (may be nil or inherit
    /// the current session fingerprint).
    public let sessionFingerprint: String?
    public let inputEvidenceRef: String?
    public let staleState: StaleState
    public let promptVersion: String?
    public let modelName: String?

    public init(
        id: UUID = UUID(),
        value: String,
        source: UnderstandingSource,
        trigger: UnderstandingTrigger,
        createdAt: Date = Date(),
        sessionFingerprint: String? = nil,
        inputEvidenceRef: String? = nil,
        staleState: StaleState = .fresh,
        promptVersion: String? = nil,
        modelName: String? = nil
    ) {
        self.id = id
        self.value = value
        self.source = source
        self.trigger = trigger
        self.createdAt = createdAt
        self.sessionFingerprint = sessionFingerprint
        self.inputEvidenceRef = inputEvidenceRef
        self.staleState = staleState
        self.promptVersion = promptVersion
        self.modelName = modelName
    }
}

// MARK: - UnderstandingField / SelectionAction / SelectionEvent

public enum UnderstandingField: String, Sendable, Equatable, CaseIterable {
    case title
    case progress
    case summary
}

public enum SelectionAction: String, Sendable, Equatable, CaseIterable {
    case adopt
}

/// Records an explicit user selection (e.g. adopting an AI candidate as
/// current). Adoption does not create a new artifact; it moves the
/// current pointer and appends a SelectionEvent.
public struct SelectionEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let field: UnderstandingField
    public let action: SelectionAction
    /// Pointer before this event; nil if pointer was unset.
    public let previousVersionID: UUID?
    /// Pointer after this event.
    public let targetVersionID: UUID
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        field: UnderstandingField,
        action: SelectionAction,
        previousVersionID: UUID?,
        targetVersionID: UUID,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.field = field
        self.action = action
        self.previousVersionID = previousVersionID
        self.targetVersionID = targetVersionID
        self.timestamp = timestamp
    }
}

// MARK: - RationaleMetadata

/// Optional explanation grounding for the current understanding package.
/// Stored as current-only metadata, not as a versioned chain.
public struct RationaleMetadata: Sendable, Equatable {
    public let text: String
    public let trigger: UnderstandingTrigger
    public let createdAt: Date
    public let basedOnTitleVersionID: UUID?
    public let basedOnProgressVersionID: UUID?
    public let basedOnSummaryVersionID: UUID?
    public let evidenceRefs: [String]
    public let staleState: StaleState

    public init(
        text: String,
        trigger: UnderstandingTrigger,
        createdAt: Date = Date(),
        basedOnTitleVersionID: UUID? = nil,
        basedOnProgressVersionID: UUID? = nil,
        basedOnSummaryVersionID: UUID? = nil,
        evidenceRefs: [String] = [],
        staleState: StaleState = .fresh
    ) {
        self.text = text
        self.trigger = trigger
        self.createdAt = createdAt
        self.basedOnTitleVersionID = basedOnTitleVersionID
        self.basedOnProgressVersionID = basedOnProgressVersionID
        self.basedOnSummaryVersionID = basedOnSummaryVersionID
        self.evidenceRefs = evidenceRefs
        self.staleState = staleState
    }
}

// MARK: - LegacyUnderstandingSnapshot

/// Pre-v0.2.9 baseline understanding read from `understanding.json` via
/// LegacyUnderstandingAdapter. All fields optional; legacy data may be
/// partial and may lack a trustworthy generation time.
public struct LegacyUnderstandingSnapshot: Sendable, Equatable {
    public let title: String?
    public let progress: String?
    public let summary: String?
    public let generatedAt: Date?
    public let modelName: String?

    public init(
        title: String? = nil,
        progress: String? = nil,
        summary: String? = nil,
        generatedAt: Date? = nil,
        modelName: String? = nil
    ) {
        self.title = title
        self.progress = progress
        self.summary = summary
        self.generatedAt = generatedAt
        self.modelName = modelName
    }
}
