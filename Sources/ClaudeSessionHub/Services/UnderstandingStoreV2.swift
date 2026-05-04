import Foundation
import Observation

/// v0.2.9 versioned understanding storage. Persists per-session
/// `UnderstandingState` to `understanding-v2.json`.
///
/// Legacy snapshot is NOT persisted here — it is derived from V1 file
/// at read time and joined into in-memory state by callers.
///
/// `@Observable` so SwiftUI views observing `state(for:)` re-render after
/// `appendArtifact`, `setCurrentPointer`, or `appendSelectionEvent` mutate
/// the in-memory state.
@Observable
public final class UnderstandingStoreV2: @unchecked Sendable {

    public enum StoreError: Error, Equatable {
        /// The given version ID is not present in the field's chain.
        case versionNotFound(field: UnderstandingField, id: UUID)
        /// The version ID exists in the chain but its source is not `.ai`.
        /// Distinguishes "wrong artifact type for this operation" from
        /// "no such artifact" so adopt-AI flows don't conflate the two.
        case versionNotAI(field: UnderstandingField, id: UUID)
    }

    public static let currentSchemaVersion = "1"

    private let filePath: String
    private let lock = NSLock()
    private var statesByID: [String: UnderstandingState] = [:]
    private var loaded = false

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("understanding-v2.json")
    }

    // MARK: - Public API

    public func state(for sessionID: String) -> UnderstandingState? {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return statesByID[sessionID]
    }

    /// Append an artifact for a field. Pointer movement rules:
    ///
    /// - Manual artifact: pointer always moves to the new artifact.
    /// - AI / Rule artifact: pointer moves only when current pointer is
    ///   nil or points to a non-manual (AI / Rule) artifact. If the
    ///   current pointer is on a manual artifact, the new AI / Rule
    ///   artifact is appended as a candidate without moving the pointer.
    /// - Summary has no manual path in v0.2.9, so the pointer is always
    ///   nil or AI; AI always moves the pointer.
    public func appendArtifact(
        for sessionID: String,
        field: UnderstandingField,
        _ artifact: UnderstandingArtifact
    ) {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()

        var state = statesByID[sessionID] ?? UnderstandingState(sessionID: sessionID)
        appendIntoState(&state, field: field, artifact: artifact)
        statesByID[sessionID] = state
        save()
    }

    /// Explicitly set the current pointer for a field. Throws
    /// `StoreError.versionNotFound` if the target ID is not in the
    /// chain. The state is left unchanged when this throws.
    public func setCurrentPointer(
        for sessionID: String,
        field: UnderstandingField,
        to versionID: UUID
    ) throws {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()

        var state = statesByID[sessionID] ?? UnderstandingState(sessionID: sessionID)
        let chain = chain(in: state, field: field)
        guard chain.contains(where: { $0.id == versionID }) else {
            throw StoreError.versionNotFound(field: field, id: versionID)
        }
        setPointer(in: &state, field: field, to: versionID)
        statesByID[sessionID] = state
        save()
    }

    /// Replace (or clear) the session's current rationale. Rationale has
    /// no version chain in v0.2.9 — new rationales replace the previous
    /// current. Pass `nil` to clear.
    public func setRationale(
        for sessionID: String,
        _ rationale: RationaleMetadata?
    ) {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()

        var state = statesByID[sessionID] ?? UnderstandingState(sessionID: sessionID)
        state.currentRationale = rationale
        statesByID[sessionID] = state
        save()
    }

    /// Update the current rationale's `staleState`. Used by edit flows
    /// that need to mark rationale stale-partial without touching the
    /// rationale's text or input references. Silent no-op if no current
    /// rationale exists for the session (rationale is optional).
    public func setRationaleStaleState(
        for sessionID: String,
        _ stale: StaleState
    ) {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()

        guard var state = statesByID[sessionID],
              let current = state.currentRationale
        else { return }

        state.currentRationale = RationaleMetadata(
            text: current.text,
            trigger: current.trigger,
            createdAt: current.createdAt,
            basedOnTitleVersionID: current.basedOnTitleVersionID,
            basedOnProgressVersionID: current.basedOnProgressVersionID,
            basedOnSummaryVersionID: current.basedOnSummaryVersionID,
            evidenceRefs: current.evidenceRefs,
            staleState: stale
        )
        statesByID[sessionID] = state
        save()
    }

    /// Append a `SelectionEvent` for adoption history. Caller is
    /// responsible for moving the pointer separately via
    /// `setCurrentPointer(...)`.
    public func appendSelectionEvent(
        for sessionID: String,
        _ event: SelectionEvent
    ) {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()

        var state = statesByID[sessionID] ?? UnderstandingState(sessionID: sessionID)
        state.selectionEvents.append(event)
        statesByID[sessionID] = state
        save()
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        guard let data = FileManager.default.contents(atPath: filePath) else {
            return // empty / missing file → empty store
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(StoreEnvelope.self, from: data)
            if envelope.schemaVersion != Self.currentSchemaVersion {
                fputs("warn: understanding-v2 schemaVersion=\(envelope.schemaVersion) not supported by this build (expected \(Self.currentSchemaVersion))\n", stderr)
                return
            }
            statesByID = envelope.states.mapValues { $0.toState() }
        } catch {
            fputs("warn: failed to decode understanding-v2.json: \(error)\n", stderr)
        }
    }

    private func save() {
        let envelope = StoreEnvelope(
            schemaVersion: Self.currentSchemaVersion,
            states: statesByID.mapValues(StoredState.init(state:))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return }
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
    }

    // MARK: - Pointer logic

    private func appendIntoState(
        _ state: inout UnderstandingState,
        field: UnderstandingField,
        artifact: UnderstandingArtifact
    ) {
        switch field {
        case .title:    state.titleVersions.append(artifact)
        case .progress: state.progressVersions.append(artifact)
        case .summary:  state.summaryVersions.append(artifact)
        }

        let shouldMove: Bool
        switch artifact.source {
        case .manual:
            shouldMove = true
        case .ai, .rule:
            shouldMove = !pointerIsManual(state: state, field: field)
        }

        if shouldMove {
            setPointer(in: &state, field: field, to: artifact.id)
        }
    }

    private func pointerIsManual(state: UnderstandingState, field: UnderstandingField) -> Bool {
        guard let pointerID = currentPointer(in: state, field: field) else {
            return false
        }
        let chain = chain(in: state, field: field)
        guard let current = chain.first(where: { $0.id == pointerID }) else {
            return false
        }
        return current.source == .manual
    }

    private func currentPointer(in state: UnderstandingState, field: UnderstandingField) -> UUID? {
        switch field {
        case .title:    return state.currentTitleVersionID
        case .progress: return state.currentProgressVersionID
        case .summary:  return state.currentSummaryVersionID
        }
    }

    private func setPointer(in state: inout UnderstandingState, field: UnderstandingField, to id: UUID) {
        switch field {
        case .title:    state.currentTitleVersionID = id
        case .progress: state.currentProgressVersionID = id
        case .summary:  state.currentSummaryVersionID = id
        }
    }

    private func chain(in state: UnderstandingState, field: UnderstandingField) -> [UnderstandingArtifact] {
        switch field {
        case .title:    return state.titleVersions
        case .progress: return state.progressVersions
        case .summary:  return state.summaryVersions
        }
    }
}

// MARK: - Codable bridges (private; mirror the model with stable wire format)

private struct StoreEnvelope: Codable {
    let schemaVersion: String
    let states: [String: StoredState]
}

/// Mirrors `UnderstandingState` minus `legacySnapshot`. Legacy is derived
/// at read time and never persisted in V2.
private struct StoredState: Codable {
    let sessionID: String
    let titleVersions: [StoredArtifact]
    let currentTitleVersionID: UUID?
    let progressVersions: [StoredArtifact]
    let currentProgressVersionID: UUID?
    let summaryVersions: [StoredArtifact]
    let currentSummaryVersionID: UUID?
    let selectionEvents: [StoredSelectionEvent]
    let currentRationale: StoredRationale?

    init(state: UnderstandingState) {
        self.sessionID = state.sessionID
        self.titleVersions = state.titleVersions.map(StoredArtifact.init(artifact:))
        self.currentTitleVersionID = state.currentTitleVersionID
        self.progressVersions = state.progressVersions.map(StoredArtifact.init(artifact:))
        self.currentProgressVersionID = state.currentProgressVersionID
        self.summaryVersions = state.summaryVersions.map(StoredArtifact.init(artifact:))
        self.currentSummaryVersionID = state.currentSummaryVersionID
        self.selectionEvents = state.selectionEvents.map(StoredSelectionEvent.init(event:))
        self.currentRationale = state.currentRationale.map(StoredRationale.init(rationale:))
    }

    func toState() -> UnderstandingState {
        UnderstandingState(
            sessionID: sessionID,
            titleVersions: titleVersions.map { $0.toArtifact() },
            currentTitleVersionID: currentTitleVersionID,
            progressVersions: progressVersions.map { $0.toArtifact() },
            currentProgressVersionID: currentProgressVersionID,
            summaryVersions: summaryVersions.map { $0.toArtifact() },
            currentSummaryVersionID: currentSummaryVersionID,
            selectionEvents: selectionEvents.map { $0.toEvent() },
            currentRationale: currentRationale?.toRationale(),
            legacySnapshot: nil
        )
    }
}

private struct StoredArtifact: Codable {
    let id: UUID
    let value: String
    let source: String
    let trigger: String
    let createdAt: Date
    let sessionFingerprint: String?
    let inputEvidenceRef: String?
    let staleState: StoredStaleState
    let promptVersion: String?
    let modelName: String?

    init(artifact: UnderstandingArtifact) {
        self.id = artifact.id
        self.value = artifact.value
        self.source = artifact.source.rawValue
        self.trigger = artifact.trigger.rawValue
        self.createdAt = artifact.createdAt
        self.sessionFingerprint = artifact.sessionFingerprint
        self.inputEvidenceRef = artifact.inputEvidenceRef
        self.staleState = StoredStaleState(state: artifact.staleState)
        self.promptVersion = artifact.promptVersion
        self.modelName = artifact.modelName
    }

    func toArtifact() -> UnderstandingArtifact {
        UnderstandingArtifact(
            id: id,
            value: value,
            source: UnderstandingSource(rawValue: source) ?? .ai,
            trigger: UnderstandingTrigger(rawValue: trigger) ?? .scan,
            createdAt: createdAt,
            sessionFingerprint: sessionFingerprint,
            inputEvidenceRef: inputEvidenceRef,
            staleState: staleState.toStaleState(),
            promptVersion: promptVersion,
            modelName: modelName
        )
    }
}

private struct StoredSelectionEvent: Codable {
    let id: UUID
    let field: String
    let action: String
    let previousVersionID: UUID?
    let targetVersionID: UUID
    let timestamp: Date

    init(event: SelectionEvent) {
        self.id = event.id
        self.field = event.field.rawValue
        self.action = event.action.rawValue
        self.previousVersionID = event.previousVersionID
        self.targetVersionID = event.targetVersionID
        self.timestamp = event.timestamp
    }

    func toEvent() -> SelectionEvent {
        SelectionEvent(
            id: id,
            field: UnderstandingField(rawValue: field) ?? .title,
            action: SelectionAction(rawValue: action) ?? .adopt,
            previousVersionID: previousVersionID,
            targetVersionID: targetVersionID,
            timestamp: timestamp
        )
    }
}

private struct StoredRationale: Codable {
    let text: String
    let trigger: String
    let createdAt: Date
    let basedOnTitleVersionID: UUID?
    let basedOnProgressVersionID: UUID?
    let basedOnSummaryVersionID: UUID?
    let evidenceRefs: [String]
    let staleState: StoredStaleState

    init(rationale: RationaleMetadata) {
        self.text = rationale.text
        self.trigger = rationale.trigger.rawValue
        self.createdAt = rationale.createdAt
        self.basedOnTitleVersionID = rationale.basedOnTitleVersionID
        self.basedOnProgressVersionID = rationale.basedOnProgressVersionID
        self.basedOnSummaryVersionID = rationale.basedOnSummaryVersionID
        self.evidenceRefs = rationale.evidenceRefs
        self.staleState = StoredStaleState(state: rationale.staleState)
    }

    func toRationale() -> RationaleMetadata {
        RationaleMetadata(
            text: text,
            trigger: UnderstandingTrigger(rawValue: trigger) ?? .manualGenerate,
            createdAt: createdAt,
            basedOnTitleVersionID: basedOnTitleVersionID,
            basedOnProgressVersionID: basedOnProgressVersionID,
            basedOnSummaryVersionID: basedOnSummaryVersionID,
            evidenceRefs: evidenceRefs,
            staleState: staleState.toStaleState()
        )
    }
}

/// Tag-based encoding for `StaleState`'s associated values.
private struct StoredStaleState: Codable {
    let kind: String
    let at: Date?
    let reason: String?

    init(state: StaleState) {
        switch state {
        case .fresh:
            self.kind = "fresh"
            self.at = nil
            self.reason = nil
        case .staleSessionUpdated(let date):
            self.kind = "staleSessionUpdated"
            self.at = date
            self.reason = nil
        case .stalePartial(let reason):
            self.kind = "stalePartial"
            self.at = nil
            self.reason = reason
        case .legacyUnknown:
            self.kind = "legacyUnknown"
            self.at = nil
            self.reason = nil
        }
    }

    func toStaleState() -> StaleState {
        switch kind {
        case "fresh": return .fresh
        case "staleSessionUpdated": return .staleSessionUpdated(at: at ?? Date())
        case "stalePartial": return .stalePartial(reason: reason ?? "")
        case "legacyUnknown": return .legacyUnknown
        default: return .fresh
        }
    }
}
