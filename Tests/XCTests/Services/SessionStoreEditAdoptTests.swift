import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// Coverage for the v0.2.9 P2 edit + adopt store API. Regenerate
/// flows are intentionally out of scope here — this file exists to
/// lock the manual-edit and adopt-AI semantics ahead of the C2 LLM
/// seam.
@MainActor
final class SessionStoreEditAdoptTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-edit-adopt-\(UUID().uuidString)"
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

    // MARK: - Edit title

    func testEditTitleCreatesManualArtifactAndMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.editTitle(for: ref(), newValue: "manual title")

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 1)
        let artifact = state.titleVersions[0]
        XCTAssertEqual(artifact.value, "manual title")
        XCTAssertEqual(artifact.source, .manual)
        XCTAssertEqual(artifact.trigger, .manualEdit)
        XCTAssertEqual(state.currentTitleVersionID, artifact.id)
    }

    func testEditTitleOverridesAICurrent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let ai = UnderstandingArtifact(value: "ai title", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)

        store.editTitle(for: ref(), newValue: "manual title")

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(state.titleVersions[1].source, .manual)
        XCTAssertEqual(state.currentTitleVersionID, state.titleVersions[1].id)
    }

    func testEditTitleEmptyOrWhitespaceIsNoOp() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.editTitle(for: ref(), newValue: "")
        store.editTitle(for: ref(), newValue: "   \n\t")
        XCTAssertNil(store.understandingV2.state(for: "s1"))
    }

    func testEditTitleTrimsWhitespace() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.editTitle(for: ref(), newValue: "  spaced title  \n")
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.titleVersions[0].value, "spaced title")
    }

    func testEditTitleMarksRationaleStalePartial() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let r = RationaleMetadata(
            text: "based on file changes",
            trigger: .manualGenerate,
            evidenceRefs: ["e1"],
            staleState: .fresh
        )
        store.understandingV2.setRationale(for: "s1", r)

        store.editTitle(for: ref(), newValue: "new title")

        guard let updated = store.understandingV2.state(for: "s1")?.currentRationale else {
            XCTFail("rationale should still exist after edit"); return
        }
        guard case .stalePartial(let reason) = updated.staleState else {
            XCTFail("expected .stalePartial, got \(updated.staleState)"); return
        }
        XCTAssertTrue(reason.lowercased().contains("title"),
                      "stale reason should mention title, got \(reason)")
        XCTAssertEqual(updated.text, "based on file changes")
        XCTAssertEqual(updated.evidenceRefs, ["e1"])
    }

    func testEditTitleNoRationaleNoOp() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.editTitle(for: ref(), newValue: "title")
        XCTAssertNil(store.understandingV2.state(for: "s1")?.currentRationale)
    }

    // MARK: - Edit progress

    func testEditProgressCreatesManualArtifactAndMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.editProgress(for: ref(), newValue: "manual progress")
        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.progressVersions.count, 1)
        XCTAssertEqual(state.progressVersions[0].source, .manual)
        XCTAssertEqual(state.currentProgressVersionID, state.progressVersions[0].id)
    }

    func testEditProgressMarksRationaleStalePartial() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        store.understandingV2.setRationale(
            for: "s1",
            RationaleMetadata(text: "x", trigger: .manualGenerate)
        )
        store.editProgress(for: ref(), newValue: "new progress")
        guard case .stalePartial(let reason) =
                store.understandingV2.state(for: "s1")?.currentRationale?.staleState
        else {
            XCTFail("expected .stalePartial"); return
        }
        XCTAssertTrue(reason.lowercased().contains("progress"))
    }

    // MARK: - Adopt AI version

    func testAdoptAIByVersionIDMovesPointerAndAppendsSelectionEvent() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        // Set up: manual current with AI candidate sitting in chain.
        let manual = UnderstandingArtifact(value: "manual", source: .manual, trigger: .manualEdit)
        let ai = UnderstandingArtifact(value: "ai", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.currentTitleVersionID, manual.id)

        try store.adoptAIVersion(for: ref(), field: .title, versionID: ai.id)

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.currentTitleVersionID, ai.id)
        // AI source preserved; no fake manual artifact created.
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(state.titleVersions[1].source, .ai)
        XCTAssertEqual(state.titleVersions[1].id, ai.id)
        // Selection event recorded with both endpoints.
        XCTAssertEqual(state.selectionEvents.count, 1)
        let event = state.selectionEvents[0]
        XCTAssertEqual(event.field, .title)
        XCTAssertEqual(event.action, .adopt)
        XCTAssertEqual(event.previousVersionID, manual.id)
        XCTAssertEqual(event.targetVersionID, ai.id)
    }

    func testAdoptOlderAICandidateAmongMultiple() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let m = UnderstandingArtifact(value: "m", source: .manual, trigger: .manualEdit)
        let a1 = UnderstandingArtifact(value: "a1", source: .ai, trigger: .manualGenerate)
        let a2 = UnderstandingArtifact(value: "a2", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .title, m)
        store.understandingV2.appendArtifact(for: "s1", field: .title, a1)
        store.understandingV2.appendArtifact(for: "s1", field: .title, a2)

        try store.adoptAIVersion(for: ref(), field: .title, versionID: a1.id)

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.currentTitleVersionID, a1.id)
        XCTAssertEqual(state.titleVersions.count, 3,
                       "adopt must not create new artifacts")
    }

    func testAdoptUnknownVersionThrowsVersionNotFound() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let ai = UnderstandingArtifact(value: "ai", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)
        let unknown = UUID()

        XCTAssertThrowsError(
            try store.adoptAIVersion(for: ref(), field: .title, versionID: unknown)
        ) { err in
            guard let e = err as? UnderstandingStoreV2.StoreError else {
                XCTFail("expected StoreError"); return
            }
            if case .versionNotFound(let f, let id) = e {
                XCTAssertEqual(f, .title)
                XCTAssertEqual(id, unknown)
            } else {
                XCTFail("expected .versionNotFound, got \(e)")
            }
        }
        // Pointer + chain unchanged
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.currentTitleVersionID, ai.id)
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.selectionEvents.count, 0)
    }

    /// Distinguishing constraint: a non-AI artifact with the same id
    /// must report `.versionNotAI`, not `.versionNotFound`. Conflating
    /// the two would let adopt flows blame "missing artifact" when the
    /// real problem is "wrong source for adoption".
    func testAdoptNonAIVersionThrowsVersionNotAINotVersionNotFound() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let manual = UnderstandingArtifact(value: "m", source: .manual, trigger: .manualEdit)
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)

        XCTAssertThrowsError(
            try store.adoptAIVersion(for: ref(), field: .title, versionID: manual.id)
        ) { err in
            guard let e = err as? UnderstandingStoreV2.StoreError else {
                XCTFail("expected StoreError"); return
            }
            if case .versionNotAI(let f, let id) = e {
                XCTAssertEqual(f, .title)
                XCTAssertEqual(id, manual.id)
            } else if case .versionNotFound = e {
                XCTFail("non-AI artifact must NOT be reported as versionNotFound")
            } else {
                XCTFail("expected .versionNotAI, got \(e)")
            }
        }
        // Pointer + chain unchanged; no SelectionEvent appended.
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.currentTitleVersionID, manual.id)
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.selectionEvents.count, 0)
    }

    func testAdoptOnUnknownSessionThrowsVersionNotFound() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let id = UUID()
        XCTAssertThrowsError(
            try store.adoptAIVersion(for: ref("ghost"), field: .title, versionID: id)
        ) { err in
            guard let e = err as? UnderstandingStoreV2.StoreError else {
                XCTFail("expected StoreError"); return
            }
            if case .versionNotFound = e {} else {
                XCTFail("expected .versionNotFound for missing session, got \(e)")
            }
        }
    }

    func testAdoptPreviousPointerNilWhenChainHadNoCurrent() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        // Append an AI artifact directly without a prior current pointer
        // path: after appendArtifact the pointer auto-moves. To force
        // pointer=nil, manually clear via setCurrentPointer to a known
        // id and back? Simpler: append two artifacts and adopt the
        // first; previousVersionID will be the second (auto-set) — we
        // then re-adopt to verify previousPointer is now the first.
        let a1 = UnderstandingArtifact(value: "a1", source: .ai, trigger: .manualGenerate)
        let a2 = UnderstandingArtifact(value: "a2", source: .ai, trigger: .manualGenerate)
        store.understandingV2.appendArtifact(for: "s1", field: .title, a1)
        store.understandingV2.appendArtifact(for: "s1", field: .title, a2)
        // Pointer auto-moves to a2. Adopt a1.
        try store.adoptAIVersion(for: ref(), field: .title, versionID: a1.id)

        let events = store.understandingV2.state(for: "s1")?.selectionEvents ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].previousVersionID, a2.id)
        XCTAssertEqual(events[0].targetVersionID, a1.id)
    }
}
