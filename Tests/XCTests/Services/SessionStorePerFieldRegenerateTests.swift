import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// C2 coverage: per-field regenerate flows funnel through the
/// `appendAIArtifact` seam. Tests synthesize artifact values directly
/// instead of going through a live LLM, so flow logic is verified
/// without an API dependency.
@MainActor
final class SessionStorePerFieldRegenerateTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-perfield-\(UUID().uuidString)"
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

    // MARK: - appendAIArtifact seam — direct invocation

    func testAppendAIArtifactCreatesAIArtifactWithModelAndTime() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let when = Date(timeIntervalSince1970: 1_700_000_000)

        store.appendAIArtifact(
            for: "s1", field: .title, value: "ai title",
            modelName: "gpt-4o", generatedAt: when
        )

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 1)
        let artifact = state.titleVersions[0]
        XCTAssertEqual(artifact.value, "ai title")
        XCTAssertEqual(artifact.source, .ai)
        XCTAssertEqual(artifact.trigger, .manualGenerate)
        XCTAssertEqual(artifact.modelName, "gpt-4o")
        XCTAssertEqual(artifact.createdAt, when)
        XCTAssertEqual(artifact.staleState, .fresh)
        XCTAssertEqual(state.currentTitleVersionID, artifact.id)
    }

    func testAppendAIArtifactPointerMovesWhenCurrentIsNil() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.appendAIArtifact(
            for: "s1", field: .title, value: "ai",
            modelName: "m", generatedAt: Date()
        )
        XCTAssertNotNil(store.understandingV2.state(for: "s1")?.currentTitleVersionID)
    }

    func testAppendAIArtifactPointerMovesWhenCurrentIsAI() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let ai1 = UnderstandingArtifact(value: "old", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai1)

        store.appendAIArtifact(
            for: "s1", field: .title, value: "new",
            modelName: "m", generatedAt: Date()
        )

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(state.currentTitleVersionID, state.titleVersions[1].id)
        XCTAssertEqual(state.titleVersions[1].value, "new")
    }

    /// Per-field regenerate equivalent: regenerateTitle when current
    /// pointer is on a manual artifact must append the AI candidate
    /// without moving the pointer (C2 rule). Verified directly through
    /// the seam.
    func testAppendAIArtifactAppendsCandidateWhenCurrentIsManual() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let manual = UnderstandingArtifact(value: "manual", source: .manual, trigger: .manualEdit)
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)

        store.appendAIArtifact(
            for: "s1", field: .title, value: "ai candidate",
            modelName: "m", generatedAt: Date()
        )

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(state.titleVersions[1].source, .ai)
        XCTAssertEqual(
            state.currentTitleVersionID, manual.id,
            "AI dual-write must not displace the manual current pointer"
        )
    }

    func testAppendAIArtifactSummaryAlwaysMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        // No manual path for summary; AI always moves pointer.
        let ai1 = UnderstandingArtifact(value: "1", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .summary, ai1)

        store.appendAIArtifact(
            for: "s1", field: .summary, value: "2",
            modelName: "m", generatedAt: Date()
        )

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.currentSummaryVersionID, state.summaryVersions.last?.id)
        XCTAssertEqual(state.summaryVersions.last?.value, "2")
    }

    // MARK: - Full regenerate semantics (manual title/progress preserved, summary moves)

    /// Full regenerate run while title and progress are manual-current:
    /// each field's AI write is appended as a candidate without moving
    /// the manual pointer; summary has no manual path so its pointer
    /// moves to the new AI artifact.
    func testFullRegenerateAppendsAICandidatesForManualHeldFieldsAndMovesSummary() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let mt = UnderstandingArtifact(value: "manual title", source: .manual, trigger: .manualEdit)
        let mp = UnderstandingArtifact(value: "manual prog", source: .manual, trigger: .manualEdit)
        store.understandingV2.appendArtifact(for: "s1", field: .title, mt)
        store.understandingV2.appendArtifact(for: "s1", field: .progress, mp)

        // Simulate full regenerate via 3 seam calls (no real LLM).
        let when = Date()
        store.appendAIArtifact(
            for: "s1", field: .title, value: "ai title",
            modelName: "gpt", generatedAt: when
        )
        store.appendAIArtifact(
            for: "s1", field: .progress, value: "ai prog",
            modelName: "gpt", generatedAt: when
        )
        store.appendAIArtifact(
            for: "s1", field: .summary, value: "ai summary",
            modelName: "gpt", generatedAt: when
        )

        let state = store.understandingV2.state(for: "s1")!
        // Title: chain has manual + ai; pointer stays on manual (candidate appended).
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(state.titleVersions[1].source, .ai)
        XCTAssertEqual(state.currentTitleVersionID, mt.id)
        // Progress: same pattern — pointer stays on manual.
        XCTAssertEqual(state.progressVersions.count, 2)
        XCTAssertEqual(state.progressVersions[1].source, .ai)
        XCTAssertEqual(state.currentProgressVersionID, mp.id)
        // Summary: only the AI artifact exists; pointer is on it.
        XCTAssertEqual(state.summaryVersions.count, 1)
        XCTAssertEqual(state.summaryVersions[0].value, "ai summary")
        XCTAssertEqual(state.currentSummaryVersionID, state.summaryVersions[0].id)
    }

    // MARK: - persistEnhancement still funnels through the seam

    /// Regression: `persistEnhancement` was reworked to call
    /// `appendAIArtifact` for each field instead of duplicating the
    /// artifact-construction logic. Verify the migration tests'
    /// expectations still hold and pointer rules remain consistent.
    func testPersistEnhancementUsesSeamAndPreservesManualPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let mt = UnderstandingArtifact(value: "manual title", source: .manual, trigger: .manualEdit)
        store.understandingV2.appendArtifact(for: "s1", field: .title, mt)

        let snap = LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "ai title",
            progress: "ai progress",
            summary: "ai summary",
            modelName: "gpt-4o",
            generatedAt: Date(),
            basedOnLastActiveAt: Date()
        )
        store.persistEnhancement(snap)

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(
            state.currentTitleVersionID, mt.id,
            "full enhance dual-write must respect manual pointer"
        )
        // Progress + summary chains gain one AI artifact each.
        XCTAssertEqual(state.progressVersions.count, 1)
        XCTAssertEqual(state.progressVersions[0].source, .ai)
        XCTAssertEqual(state.summaryVersions.count, 1)
        XCTAssertEqual(state.summaryVersions[0].source, .ai)
    }

    // MARK: - Public regenerate methods reach the seam (unconfigured path)

    func testRegenerateTitleThrowsWhenUnconfigured() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        // SettingsStore default config is unconfigured.
        do {
            try await store.regenerateTitle(for: ref())
            XCTFail("expected notConfigured")
        } catch LLMClient.LLMError.notConfigured {
            // ok
        } catch {
            XCTFail("expected LLMError.notConfigured, got \(error)")
        }
    }

    func testRegenerateProgressThrowsWhenUnconfigured() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        do {
            try await store.regenerateProgress(for: ref())
            XCTFail("expected notConfigured")
        } catch LLMClient.LLMError.notConfigured {} catch {
            XCTFail("got \(error)")
        }
    }

    func testRegenerateSummaryThrowsWhenUnconfigured() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        do {
            try await store.regenerateSummary(for: ref())
            XCTFail("expected notConfigured")
        } catch LLMClient.LLMError.notConfigured {} catch {
            XCTFail("got \(error)")
        }
    }

    // MARK: - LLMEnhancer.enhanceField unconfigured

    func testLLMEnhancerEnhanceFieldReturnsNilWhenUnconfigured() async {
        let enhancer = LLMEnhancer(config: LLMConfig())
        let signals = SessionSignals(sessionID: "s1")
        let result = await enhancer.enhanceField(
            .title, signals: signals, basedOnLastActiveAt: Date()
        )
        XCTAssertNil(result)
    }
}
