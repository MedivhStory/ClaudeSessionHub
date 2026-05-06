import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// Stub provider for `SessionStoreResolvedStaleStateTests` — feeds a
/// fixed `[SessionSummary]` through `ScanCoordinator` so `performScan`
/// can populate `SessionStore.sessions` (which is `private(set)` and
/// therefore the only test seam available is the scan path).
private final class MockSessionProvider: AgentProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String = "Mock"
    let capabilities: ProviderCapabilities = []
    private let sessions: [SessionSummary]

    init(providerID: String = "mock", sessions: [SessionSummary]) {
        self.id = providerID
        self.sessions = sessions
    }

    func discoverSessions() async throws -> [SessionSummary] { sessions }
    func loadSessionDetail(for ref: SessionRef) async throws -> SessionDetail {
        throw CocoaError(.featureUnsupported)
    }
    func makeResumeTarget(for ref: SessionRef) throws -> ResumeTarget {
        ResumeTarget(executable: "mock", arguments: [], workingDirectory: nil, displayCommand: "mock")
    }
    func refreshRuntimeState(for refs: [SessionRef]) async -> [SessionRef: SessionRuntimeState] { [:] }
}

/// C2 coverage: pure derivation rules for
/// `UnderstandingDisplayPolicy.staleStateBy(...)`.
///
/// Rule order (rev.3):
/// 1. Legacy first → `.legacyUnknown`
/// 2. Stored `.stalePartial(reason)` preserved
/// 3. Stored `.fresh` + session drift → `.staleSessionUpdated(at:)`
/// 4. Else → `.fresh`
final class StaleStateDerivationTests: XCTestCase {

    private let policy = UnderstandingDisplayPolicy()

    // MARK: - Rule 1: Legacy first

    func testLegacyAlwaysLegacyUnknownEvenWithOldGeneratedAt() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 1_000_000)
        let result = policy.staleStateBy(
            resolvedSource: .legacy,
            storedStale: .legacyUnknown,
            artifactCreatedAt: oldDate,
            sessionLastActiveAt: newDate
        )
        XCTAssertEqual(result, .legacyUnknown)
    }

    func testLegacySourceOverridesStoredPartial() {
        let result = policy.staleStateBy(
            resolvedSource: .legacy,
            storedStale: .stalePartial(reason: "x"),
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(
            result, .legacyUnknown,
            "legacy source must rank ahead of stored partial"
        )
    }

    // MARK: - Rule 2: Stored partial preserved

    func testStoredPartialStaleNotOverriddenByDerivation() {
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .stalePartial(reason: "title edited"),
            artifactCreatedAt: Date(timeIntervalSince1970: 100),
            sessionLastActiveAt: Date(timeIntervalSince1970: 1_000_000)
        )
        XCTAssertEqual(
            result, .stalePartial(reason: "title edited"),
            "session drift must not displace a stored .stalePartial reason"
        )
    }

    func testStoredPartialPreservedRegardlessOfManualSource() {
        let result = policy.staleStateBy(
            resolvedSource: .manual,
            storedStale: .stalePartial(reason: "edited"),
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(result, .stalePartial(reason: "edited"))
    }

    // MARK: - Rule 3: Session drift

    func testSessionUpdatedAfterArtifactDerivesStale() {
        let createdAt = Date(timeIntervalSince1970: 1000)
        let lastActive = Date(timeIntervalSince1970: 2000)
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: createdAt,
            sessionLastActiveAt: lastActive
        )
        XCTAssertEqual(result, .staleSessionUpdated(at: lastActive))
    }

    func testSessionNotUpdatedAfterArtifactStaysFresh() {
        let createdAt = Date(timeIntervalSince1970: 2000)
        let lastActive = Date(timeIntervalSince1970: 1000)
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: createdAt,
            sessionLastActiveAt: lastActive
        )
        XCTAssertEqual(result, .fresh)
    }

    func testEqualTimestampsIsFresh() {
        let when = Date(timeIntervalSince1970: 1000)
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: when,
            sessionLastActiveAt: when
        )
        XCTAssertEqual(
            result, .fresh,
            "drift requires lastActive STRICTLY greater than createdAt"
        )
    }

    // MARK: - Rule 4: fallback

    func testNilTimestampsReturnFresh() {
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: nil,
            sessionLastActiveAt: nil
        )
        XCTAssertEqual(result, .fresh)
    }

    func testNilStoredStaleReturnsFresh() {
        // Rule/uuid/none sources have nil staleState; derivation must
        // fall through to .fresh.
        let result = policy.staleStateBy(
            resolvedSource: .rule,
            storedStale: nil,
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(result, .fresh)
    }

    func testStoredStaleSessionUpdatedNotPreserved() {
        // Spec: derivation only fires when stored is .fresh. A stored
        // .staleSessionUpdated falls through rule 3's preconditions and
        // ends at rule 4 → .fresh. Drift is recomputed at read time, not
        // trusted from storage.
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .staleSessionUpdated(at: Date()),
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(result, .fresh)
    }
}

// MARK: - SessionStore wiring

/// C2 wiring coverage: `SessionStore.resolvedStaleState(for:field:)`
/// composes `resolved*` + chain artifact lookup + `staleStateBy(...)`.
@MainActor
final class SessionStoreResolvedStaleStateTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-stale-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func makeStore(directory: String) -> SessionStore {
        SessionStore(
            coordinator: ScanCoordinator(providers: []),
            settings: SettingsStore(directory: directory, secretStore: InMemorySecretStore()),
            understandingStore: UnderstandingStore(directory: directory),
            understandingV2: UnderstandingStoreV2(directory: directory),
            legacyAdapter: LegacyUnderstandingAdapter(directory: directory)
        )
    }

    private func ref(_ sid: String = "s1") -> SessionRef {
        SessionRef(providerID: "claude", sessionID: sid)
    }

    /// With no V2 state and no legacy, all fields resolve to rule/uuid/none
    /// sources; derivation falls through to `.fresh`.
    func testEmptyResolvesFresh() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .title), .fresh)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .progress), .fresh)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .summary), .fresh)
    }

    /// Legacy-only session: rule 1 fires regardless of artifact dates.
    func testLegacyOnlyReturnsLegacyUnknown() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        UnderstandingStore(directory: dir).setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy",
            progress: nil,
            summary: nil,
            modelName: "m",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ))
        let store = makeStore(directory: dir)
        XCTAssertEqual(
            store.resolvedStaleState(for: ref(), field: .title),
            .legacyUnknown
        )
    }

    /// Stored partial on a V2 manual artifact survives derivation.
    func testStoredPartialPreservedThroughSessionStore() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let artifact = UnderstandingArtifact(
            value: "manual edited",
            source: .manual,
            trigger: .manualEdit,
            createdAt: Date(timeIntervalSince1970: 1000),
            staleState: .stalePartial(reason: "user-edited")
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, artifact)
        XCTAssertEqual(
            store.resolvedStaleState(for: ref(), field: .title),
            .stalePartial(reason: "user-edited")
        )
    }

    // MARK: - resolvedStaleExplanation (C4)

    func testResolvedStaleExplanationFreshReturnsNil() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        XCTAssertNil(store.resolvedStaleExplanation(for: ref(), field: .title))
    }

    func testResolvedStaleExplanationLegacyReturnsBaselineNotice() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        UnderstandingStore(directory: dir).setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy",
            progress: nil,
            summary: nil,
            modelName: "m",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ))
        let store = makeStore(directory: dir)
        XCTAssertEqual(
            store.resolvedStaleExplanation(for: ref(), field: .title),
            "Pre-v0.2.9 旧基线,无法判断时效"
        )
    }

    func testResolvedStaleExplanationStoredPartialReturnsReason() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let artifact = UnderstandingArtifact(
            value: "edited",
            source: .manual,
            trigger: .manualEdit,
            createdAt: Date(timeIntervalSince1970: 1000),
            staleState: .stalePartial(reason: "user edited")
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, artifact)
        XCTAssertEqual(
            store.resolvedStaleExplanation(for: ref(), field: .title),
            "此字段标注为 stale: user edited"
        )
    }

    // MARK: - Regenerate clears stale (C4 acceptance row)

    /// rev.3 acceptance: "Regenerate refreshes including legacy/stale
    /// (gated only on isConfigured)". Drives the seam used by the public
    /// `regenerate*` methods so we can verify the post-regenerate state
    /// without an actual LLM call: the field flips from `.legacy` to
    /// `.ai`, staleState becomes `.fresh`, and the explanation clears.
    func testRegenerateOnStaleLegacySessionAppendsAIArtifactAndClearsBadge() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        UnderstandingStore(directory: dir).setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy title",
            progress: nil,
            summary: nil,
            modelName: "old",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ))
        let store = makeStore(directory: dir)

        XCTAssertEqual(store.resolvedTitle(for: ref()).source, .legacy)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .title), .legacyUnknown)
        XCTAssertEqual(
            store.resolvedStaleExplanation(for: ref(), field: .title),
            "Pre-v0.2.9 旧基线,无法判断时效"
        )

        // Simulate the per-field regenerate's terminal step (the public
        // `regenerateTitle` requires a configured LLM client).
        store.appendAIArtifact(
            for: "s1",
            field: .title,
            value: "ai title",
            modelName: "gpt",
            generatedAt: Date(timeIntervalSince1970: 5000)
        )

        XCTAssertEqual(store.resolvedTitle(for: ref()).source, .ai)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .title), .fresh)
        XCTAssertNil(
            store.resolvedStaleExplanation(for: ref(), field: .title),
            "fresh state must produce no explanation text"
        )
    }

    /// C2.1: real-drift wiring. Populate `sessions[]` through the scan
    /// path with a SessionSummary whose `lastActiveAt` is strictly after
    /// the artifact's `createdAt`, then assert the store hands back
    /// `.staleSessionUpdated(at: lastActiveAt)`. This complements the
    /// pure-policy drift test — the prior wiring tests covered legacy /
    /// stored-partial / empty paths but never reached rule 3 because
    /// `sessions[]` was empty.
    func testSessionDriftWiresThroughToStaleSessionUpdated() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let artifactCreatedAt = Date(timeIntervalSince1970: 1000)
        let lastActive = Date(timeIntervalSince1970: 5000)

        let summary = SessionSummary(
            ref: SessionRef(providerID: "mock", sessionID: "s1"),
            title: "drift test",
            currentTaskSummary: nil,
            runtimeState: .active,
            taskPhase: .inProgress,
            cwd: "/tmp",
            branch: "main",
            turnCount: 1, filesTouched: 0, recentErrorCount: 0,
            createdAt: Date(timeIntervalSince1970: 500),
            lastActiveAt: lastActive,
            contextUsage: nil
        )
        let provider = MockSessionProvider(providerID: "mock", sessions: [summary])

        let store = SessionStore(
            coordinator: ScanCoordinator(providers: [provider]),
            settings: SettingsStore(directory: dir, secretStore: InMemorySecretStore()),
            understandingStore: UnderstandingStore(directory: dir),
            understandingV2: UnderstandingStoreV2(directory: dir),
            legacyAdapter: LegacyUnderstandingAdapter(directory: dir)
        )

        let artifact = UnderstandingArtifact(
            value: "ai title",
            source: .ai,
            trigger: .manualGenerate,
            createdAt: artifactCreatedAt,
            staleState: .fresh
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, artifact)

        // Drive the scan path so `sessions[]` is populated; no real I/O
        // happens because MockSessionProvider hands back the fixture
        // directly.
        await store.performScan()
        XCTAssertEqual(store.sessions.count, 1, "scan should have populated one session")

        let driftRef = SessionRef(providerID: "mock", sessionID: "s1")
        let stale = store.resolvedStaleState(for: driftRef, field: .title)
        XCTAssertEqual(
            stale, .staleSessionUpdated(at: lastActive),
            "lastActiveAt > createdAt + stored .fresh must derive .staleSessionUpdated(at: lastActiveAt)"
        )

        // C4 wire-through: humanized explanation reaches the panel-bound
        // accessor with the right hour count. 4000s drift → 1 小时
        // (Int truncation; sub-hour drifts are clamped to ≥ 1).
        XCTAssertEqual(
            store.resolvedStaleExplanation(for: driftRef, field: .title),
            "会话在生成后又更新了 1 小时,此字段可能不再可信"
        )
    }
}
