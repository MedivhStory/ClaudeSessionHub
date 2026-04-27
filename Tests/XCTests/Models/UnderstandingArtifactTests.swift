import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class UnderstandingArtifactTests: XCTestCase {

    // MARK: - UnderstandingArtifact

    func testUnderstandingArtifactDefaults() {
        let artifact = UnderstandingArtifact(
            value: "test title",
            source: .ai,
            trigger: .manualGenerate
        )
        XCTAssertEqual(artifact.value, "test title")
        XCTAssertEqual(artifact.source, .ai)
        XCTAssertEqual(artifact.trigger, .manualGenerate)
        XCTAssertEqual(artifact.staleState, .fresh)
        XCTAssertNil(artifact.sessionFingerprint)
        XCTAssertNil(artifact.inputEvidenceRef)
        XCTAssertNil(artifact.promptVersion)
        XCTAssertNil(artifact.modelName)
    }

    func testUnderstandingArtifactExplicitFields() {
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let artifact = UnderstandingArtifact(
            id: id,
            value: "hello",
            source: .manual,
            trigger: .manualEdit,
            createdAt: when,
            sessionFingerprint: "abc123",
            inputEvidenceRef: "evidence-1",
            staleState: .stalePartial(reason: "title edited"),
            promptVersion: nil,
            modelName: nil
        )
        XCTAssertEqual(artifact.id, id)
        XCTAssertEqual(artifact.createdAt, when)
        XCTAssertEqual(artifact.sessionFingerprint, "abc123")
        XCTAssertEqual(artifact.inputEvidenceRef, "evidence-1")
        XCTAssertEqual(artifact.staleState, .stalePartial(reason: "title edited"))
    }

    // MARK: - StaleState equality across associated values

    func testStaleStateEqualityFresh() {
        XCTAssertEqual(StaleState.fresh, StaleState.fresh)
        XCTAssertNotEqual(StaleState.fresh, StaleState.legacyUnknown)
    }

    func testStaleStateSessionUpdatedCarriesDate() {
        let now = Date()
        XCTAssertEqual(StaleState.staleSessionUpdated(at: now),
                       StaleState.staleSessionUpdated(at: now))
        XCTAssertNotEqual(StaleState.staleSessionUpdated(at: now),
                          StaleState.staleSessionUpdated(at: now.addingTimeInterval(1)))
    }

    func testStaleStatePartialDistinguishesByReason() {
        XCTAssertEqual(StaleState.stalePartial(reason: "x"),
                       StaleState.stalePartial(reason: "x"))
        XCTAssertNotEqual(StaleState.stalePartial(reason: "x"),
                          StaleState.stalePartial(reason: "y"))
    }

    // MARK: - SelectionEvent

    func testSelectionEventCarriesPreviousAndTarget() {
        let prev = UUID()
        let target = UUID()
        let event = SelectionEvent(
            field: .title,
            action: .adopt,
            previousVersionID: prev,
            targetVersionID: target
        )
        XCTAssertEqual(event.previousVersionID, prev)
        XCTAssertEqual(event.targetVersionID, target)
        XCTAssertEqual(event.field, .title)
        XCTAssertEqual(event.action, .adopt)
    }

    func testSelectionEventNilPreviousIsLegal() {
        let target = UUID()
        let event = SelectionEvent(
            field: .progress,
            action: .adopt,
            previousVersionID: nil,
            targetVersionID: target
        )
        XCTAssertNil(event.previousVersionID)
        XCTAssertEqual(event.targetVersionID, target)
    }

    // MARK: - LegacyUnderstandingSnapshot all-optional

    func testLegacySnapshotEmpty() {
        let empty = LegacyUnderstandingSnapshot()
        XCTAssertNil(empty.title)
        XCTAssertNil(empty.progress)
        XCTAssertNil(empty.summary)
        XCTAssertNil(empty.generatedAt)
        XCTAssertNil(empty.modelName)
    }

    func testLegacySnapshotPartial() {
        let titleOnly = LegacyUnderstandingSnapshot(title: "old title")
        XCTAssertEqual(titleOnly.title, "old title")
        XCTAssertNil(titleOnly.progress)
        XCTAssertNil(titleOnly.summary)
    }

    // MARK: - RationaleMetadata

    func testRationaleMetadataDefaults() {
        let rationale = RationaleMetadata(
            text: "based on file changes",
            trigger: .manualGenerate
        )
        XCTAssertEqual(rationale.text, "based on file changes")
        XCTAssertEqual(rationale.trigger, .manualGenerate)
        XCTAssertEqual(rationale.staleState, .fresh)
        XCTAssertTrue(rationale.evidenceRefs.isEmpty)
        XCTAssertNil(rationale.basedOnTitleVersionID)
    }

    // MARK: - UnderstandingState

    func testUnderstandingStateDefaults() {
        let state = UnderstandingState(sessionID: "abc")
        XCTAssertEqual(state.sessionID, "abc")
        XCTAssertEqual(state.id, "abc")
        XCTAssertTrue(state.titleVersions.isEmpty)
        XCTAssertTrue(state.progressVersions.isEmpty)
        XCTAssertTrue(state.summaryVersions.isEmpty)
        XCTAssertTrue(state.selectionEvents.isEmpty)
        XCTAssertNil(state.currentTitleVersionID)
        XCTAssertNil(state.currentProgressVersionID)
        XCTAssertNil(state.currentSummaryVersionID)
        XCTAssertNil(state.currentRationale)
        XCTAssertNil(state.legacySnapshot)
    }

    func testUnderstandingStateMutability() {
        var state = UnderstandingState(sessionID: "abc")
        let artifact = UnderstandingArtifact(
            value: "title",
            source: .ai,
            trigger: .manualGenerate
        )
        state.titleVersions.append(artifact)
        state.currentTitleVersionID = artifact.id
        XCTAssertEqual(state.titleVersions.count, 1)
        XCTAssertEqual(state.currentTitleVersionID, artifact.id)
    }

    // MARK: - Field / source / trigger / action enums

    func testEnumCaseAllCases() {
        XCTAssertEqual(UnderstandingField.allCases, [.title, .progress, .summary])
        XCTAssertEqual(UnderstandingSource.allCases, [.rule, .ai, .manual])
        XCTAssertEqual(UnderstandingTrigger.allCases, [.scan, .manualGenerate, .manualEdit])
        XCTAssertEqual(SelectionAction.allCases, [.adopt])
    }
}
