import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class UnderstandingDisplayPolicyTests: XCTestCase {

    private let policy = UnderstandingDisplayPolicy()

    private func makeArtifact(
        value: String,
        source: UnderstandingSource,
        stale: StaleState = .fresh
    ) -> UnderstandingArtifact {
        UnderstandingArtifact(
            value: value,
            source: source,
            trigger: source == .manual ? .manualEdit : .manualGenerate,
            staleState: stale
        )
    }

    private func emptyState(sessionID: String = "s1") -> UnderstandingState {
        UnderstandingState(sessionID: sessionID)
    }

    // MARK: - Title precedence

    func testTitleAllNilFallsToUUIDPrefix() {
        let r = policy.resolveTitle(
            state: nil, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "abcdefghijkl"
        )
        XCTAssertEqual(r.value, "abcdefgh")
        XCTAssertEqual(r.source, .uuidPrefix)
        XCTAssertNil(r.staleState)
        XCTAssertNil(r.artifactID)
        XCTAssertFalse(r.invalidPointer)
    }

    func testTitleRuleFallback() {
        let r = policy.resolveTitle(
            state: nil, legacy: nil, ruleTitle: "rule title",
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "rule title")
        XCTAssertEqual(r.source, .rule)
        XCTAssertNil(r.staleState)
        XCTAssertNil(r.artifactID)
    }

    func testTitleLegacyOverRule() {
        let legacy = LegacyUnderstandingSnapshot(title: "legacy title")
        let r = policy.resolveTitle(
            state: nil, legacy: legacy, ruleTitle: "rule title",
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "legacy title")
        XCTAssertEqual(r.source, .legacy)
        XCTAssertEqual(r.staleState, .legacyUnknown)
        XCTAssertNil(r.artifactID)
    }

    func testTitleAIOverLegacy() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai title", source: .ai)
        state.titleVersions = [ai]
        let legacy = LegacyUnderstandingSnapshot(title: "legacy title")
        let r = policy.resolveTitle(
            state: state, legacy: legacy, ruleTitle: "rule",
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "ai title")
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.staleState, .fresh)
        XCTAssertEqual(r.artifactID, ai.id)
    }

    func testTitleManualOverAINilPointer() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai title", source: .ai)
        let manual = makeArtifact(value: "manual title", source: .manual)
        state.titleVersions = [ai, manual]
        // currentTitleVersionID is nil → fall through precedence
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "manual title")
        XCTAssertEqual(r.source, .manual)
        XCTAssertEqual(r.artifactID, manual.id)
    }

    func testTitleLatestAIWinsAmongAIArtifacts() {
        var state = emptyState()
        let ai1 = makeArtifact(value: "ai1", source: .ai)
        let ai2 = makeArtifact(value: "ai2", source: .ai)
        state.titleVersions = [ai1, ai2]
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "ai2")
        XCTAssertEqual(r.artifactID, ai2.id)
    }

    func testTitleLatestManualWinsAmongManualArtifacts() {
        var state = emptyState()
        let m1 = makeArtifact(value: "m1", source: .manual)
        let m2 = makeArtifact(value: "m2", source: .manual)
        state.titleVersions = [m1, m2]
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "m2")
        XCTAssertEqual(r.artifactID, m2.id)
    }

    // MARK: - Pointer overrides precedence

    func testTitlePointerOverridesPrecedenceForAI() {
        var state = emptyState()
        let manual = makeArtifact(value: "manual", source: .manual)
        let ai = makeArtifact(value: "ai", source: .ai)
        state.titleVersions = [manual, ai]
        // Adopt AI: pointer set to AI artifact even though manual is in chain
        state.currentTitleVersionID = ai.id
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "ai")
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.artifactID, ai.id)
        XCTAssertFalse(r.invalidPointer)
    }

    func testTitlePointerOnManualWithNewerAIInChain() {
        var state = emptyState()
        let manual = makeArtifact(value: "manual", source: .manual)
        let ai = makeArtifact(value: "ai", source: .ai)
        state.titleVersions = [manual, ai]
        state.currentTitleVersionID = manual.id
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.value, "manual")
        XCTAssertEqual(r.source, .manual)
        XCTAssertEqual(r.artifactID, manual.id)
    }

    // MARK: - Invalid pointer

    func testTitleInvalidPointerFallsBackToChain() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai", source: .ai)
        state.titleVersions = [ai]
        state.currentTitleVersionID = UUID() // not in chain
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertTrue(r.invalidPointer)
        XCTAssertEqual(r.value, "ai")
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.artifactID, ai.id)
    }

    func testTitleInvalidPointerFallsBackToLegacy() {
        var state = emptyState()
        // Empty chain; pointer is set but invalid
        state.currentTitleVersionID = UUID()
        let legacy = LegacyUnderstandingSnapshot(title: "legacy")
        let r = policy.resolveTitle(
            state: state, legacy: legacy, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertTrue(r.invalidPointer)
        XCTAssertEqual(r.source, .legacy)
        XCTAssertEqual(r.value, "legacy")
    }

    func testTitleInvalidPointerFallsBackToUUID() {
        var state = emptyState()
        state.currentTitleVersionID = UUID()
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "deadbeef-1234"
        )
        XCTAssertTrue(r.invalidPointer)
        XCTAssertEqual(r.source, .uuidPrefix)
        XCTAssertEqual(r.value, "deadbeef")
    }

    // MARK: - StaleState propagation

    func testTitleStaleStateFromArtifact() {
        var state = emptyState()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let ai = makeArtifact(value: "ai", source: .ai, stale: .staleSessionUpdated(at: when))
        state.titleVersions = [ai]
        let r = policy.resolveTitle(
            state: state, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.staleState, .staleSessionUpdated(at: when))
    }

    func testLegacyStaleIsLegacyUnknown() {
        let legacy = LegacyUnderstandingSnapshot(title: "x")
        let r = policy.resolveTitle(
            state: nil, legacy: legacy, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.staleState, .legacyUnknown)
    }

    func testRuleStaleIsNil() {
        let r = policy.resolveTitle(
            state: nil, legacy: nil, ruleTitle: "rule",
            sessionIDForFallback: "s1"
        )
        XCTAssertNil(r.staleState)
    }

    func testUUIDStaleIsNil() {
        let r = policy.resolveTitle(
            state: nil, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "abc"
        )
        XCTAssertNil(r.staleState)
    }

    // MARK: - Progress precedence

    func testProgressEmptyReturnsNone() {
        let r = policy.resolveProgress(
            state: nil, legacy: nil, ruleProgress: nil
        )
        XCTAssertEqual(r.source, .none)
        XCTAssertNil(r.value)
        XCTAssertNil(r.staleState)
        XCTAssertFalse(r.invalidPointer)
    }

    func testProgressRuleFallback() {
        let r = policy.resolveProgress(
            state: nil, legacy: nil, ruleProgress: "rule progress"
        )
        XCTAssertEqual(r.source, .rule)
        XCTAssertEqual(r.value, "rule progress")
        XCTAssertNil(r.staleState)
    }

    func testProgressLegacyOverRule() {
        let legacy = LegacyUnderstandingSnapshot(progress: "legacy progress")
        let r = policy.resolveProgress(
            state: nil, legacy: legacy, ruleProgress: "rule progress"
        )
        XCTAssertEqual(r.source, .legacy)
        XCTAssertEqual(r.value, "legacy progress")
        XCTAssertEqual(r.staleState, .legacyUnknown)
    }

    func testProgressAIOverLegacy() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai prog", source: .ai)
        state.progressVersions = [ai]
        let legacy = LegacyUnderstandingSnapshot(progress: "legacy prog")
        let r = policy.resolveProgress(
            state: state, legacy: legacy, ruleProgress: nil
        )
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai prog")
    }

    func testProgressManualOverAI() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai prog", source: .ai)
        let manual = makeArtifact(value: "manual prog", source: .manual)
        state.progressVersions = [ai, manual]
        let r = policy.resolveProgress(
            state: state, legacy: nil, ruleProgress: nil
        )
        XCTAssertEqual(r.source, .manual)
        XCTAssertEqual(r.value, "manual prog")
        XCTAssertEqual(r.artifactID, manual.id)
    }

    func testProgressPointerOverride() {
        var state = emptyState()
        let manual = makeArtifact(value: "manual", source: .manual)
        let ai = makeArtifact(value: "ai", source: .ai)
        state.progressVersions = [manual, ai]
        state.currentProgressVersionID = ai.id
        let r = policy.resolveProgress(
            state: state, legacy: nil, ruleProgress: nil
        )
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai")
    }

    func testProgressInvalidPointerFallsBack() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai", source: .ai)
        state.progressVersions = [ai]
        state.currentProgressVersionID = UUID()
        let r = policy.resolveProgress(
            state: state, legacy: nil, ruleProgress: nil
        )
        XCTAssertTrue(r.invalidPointer)
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai")
    }

    // MARK: - Summary precedence (no manual path)

    func testSummaryEmptyReturnsNone() {
        let r = policy.resolveSummary(state: nil, legacy: nil)
        XCTAssertEqual(r.source, .none)
        XCTAssertNil(r.value)
    }

    func testSummaryAIOnly() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai summary", source: .ai)
        state.summaryVersions = [ai]
        let r = policy.resolveSummary(state: state, legacy: nil)
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai summary")
        XCTAssertEqual(r.artifactID, ai.id)
    }

    func testSummaryAIOverLegacy() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai summary", source: .ai)
        state.summaryVersions = [ai]
        let legacy = LegacyUnderstandingSnapshot(summary: "legacy summary")
        let r = policy.resolveSummary(state: state, legacy: legacy)
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai summary")
    }

    func testSummaryLegacyOnly() {
        let legacy = LegacyUnderstandingSnapshot(summary: "legacy summary")
        let r = policy.resolveSummary(state: nil, legacy: legacy)
        XCTAssertEqual(r.source, .legacy)
        XCTAssertEqual(r.value, "legacy summary")
        XCTAssertEqual(r.staleState, .legacyUnknown)
    }

    func testSummaryNoManualFallbackPath() {
        // Summary precedence has no manual step. Even if a manual artifact
        // somehow ends up in the summary chain (not produced by any code
        // path in v0.2.9), the precedence walk skips manual: chain has no
        // AI, no legacy summary, so result is .none.
        var state = emptyState()
        let manual = makeArtifact(value: "manual summary", source: .manual)
        state.summaryVersions = [manual]
        let r = policy.resolveSummary(state: state, legacy: nil)
        XCTAssertEqual(r.source, .none)
        XCTAssertNil(r.value)
    }

    func testSummaryInvalidPointerFallsBackToAI() {
        var state = emptyState()
        let ai = makeArtifact(value: "ai", source: .ai)
        state.summaryVersions = [ai]
        state.currentSummaryVersionID = UUID()
        let r = policy.resolveSummary(state: state, legacy: nil)
        XCTAssertTrue(r.invalidPointer)
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai")
    }

    // MARK: - Empty / partial legacy fields

    func testEmptyLegacyTitleStringFallsThrough() {
        // A legacy snapshot with title="" should not block fallback.
        let legacy = LegacyUnderstandingSnapshot(title: "")
        let r = policy.resolveTitle(
            state: nil, legacy: legacy, ruleTitle: "rule",
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(r.source, .rule)
        XCTAssertEqual(r.value, "rule")
    }

    func testLegacyTitleOnlyDoesNotProvideProgressOrSummary() {
        let legacy = LegacyUnderstandingSnapshot(title: "x")
        let progRes = policy.resolveProgress(
            state: nil, legacy: legacy, ruleProgress: "rule prog"
        )
        XCTAssertEqual(progRes.source, .rule)
        XCTAssertEqual(progRes.value, "rule prog")

        let summaryRes = policy.resolveSummary(state: nil, legacy: legacy)
        XCTAssertEqual(summaryRes.source, .none)
        XCTAssertNil(summaryRes.value)
    }

    func testLegacyTitleAndProgressDoesNotProvideSummary() {
        let legacy = LegacyUnderstandingSnapshot(title: "x", progress: "y")
        let r = policy.resolveSummary(state: nil, legacy: legacy)
        XCTAssertEqual(r.source, .none)
    }

    // MARK: - Source enum coverage

    func testResolvedSourceAllCases() {
        XCTAssertEqual(
            ResolvedSource.allCases,
            [.ai, .manual, .rule, .legacy, .uuidPrefix, .none]
        )
    }
}
