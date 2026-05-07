import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// Stub provider that hands back a fixed `[SessionSummary]` so
/// `performScan` can populate `SessionStore.sessions[]` without I/O.
/// Mirrors the same pattern used in `StaleStateDerivationTests`.
private final class MockEvidenceProvider: AgentProvider, @unchecked Sendable {
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

/// C2 wiring coverage: `SessionStore.evidence(for:) -> EvidencePackage`
/// composes through real `SessionSummary` from `sessions[]` + computed
/// `relations(for:)`. C1's pure composer rules already cover per-category
/// emission; these tests focus on the wiring path.
@MainActor
final class SessionStoreEvidenceTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-evidence-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func makeStore(directory: String, providers: [AgentProvider] = []) -> SessionStore {
        SessionStore(
            coordinator: ScanCoordinator(providers: providers),
            settings: SettingsStore(directory: directory, secretStore: InMemorySecretStore()),
            understandingStore: UnderstandingStore(directory: directory),
            understandingV2: UnderstandingStoreV2(directory: directory),
            legacyAdapter: LegacyUnderstandingAdapter(directory: directory)
        )
    }

    private func makeSession(
        sessionID: String,
        cwd: String? = nil,
        branch: String? = nil,
        filesTouched: Int = 0,
        taskPhase: TaskPhase = .unknown,
        lastProgress: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1000),
        lastActiveAt: Date = Date(timeIntervalSince1970: 2000)
    ) -> SessionSummary {
        SessionSummary(
            ref: SessionRef(providerID: "mock", sessionID: sessionID),
            title: "test",
            currentTaskSummary: nil,
            runtimeState: .active,
            taskPhase: taskPhase,
            cwd: cwd,
            branch: branch,
            turnCount: 0,
            filesTouched: filesTouched,
            recentErrorCount: 0,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt,
            contextUsage: nil,
            smartTitle: nil,
            lastProgress: lastProgress,
            entrypoint: nil
        )
    }

    private func ref(_ sid: String) -> SessionRef {
        SessionRef(providerID: "mock", sessionID: sid)
    }

    // MARK: - Empty / unknown ref

    func testEvidenceForUnknownSessionReturnsEmpty() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let pkg = store.evidence(for: ref("ghost"))
        XCTAssertTrue(pkg.isEmpty, "unknown ref must return empty package, not crash")
    }

    // MARK: - Composes from real SessionSummary

    func testEvidenceComposesPopulatedSessionFromScan() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let session = makeSession(
            sessionID: "s1",
            cwd: "/Users/me/Documents/repoA",
            branch: "feature/x",
            filesTouched: 5,
            taskPhase: .inProgress,
            lastProgress: "midway through refactor"
        )
        let provider = MockEvidenceProvider(sessions: [session])
        let store = makeStore(directory: dir, providers: [provider])

        await store.performScan()
        XCTAssertEqual(store.sessions.count, 1)

        let pkg = store.evidence(for: ref("s1"))
        // 6 categories: recentFiles, timeAnchors, branchCwd, projectName,
        // currentPhase, latestProgress. relatedSessions omitted (only one
        // session in the store).
        XCTAssertEqual(
            pkg.items.map(\.category),
            [.recentFiles, .timeAnchors, .branchCwd, .projectName, .currentPhase, .latestProgress]
        )
    }

    // MARK: - Wiring through relations(for:)

    func testEvidenceIncludesRelatedSessionsViaStoreRelations() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        // Two sessions on the same cwd + branch produce a sameBranch
        // relation via `SessionStore.relations(for:)`. evidence(for:)
        // must surface the relation in the relatedSessions category.
        let s1 = makeSession(
            sessionID: "s1",
            cwd: "/repo",
            branch: "main",
            filesTouched: 1,
            taskPhase: .inProgress
        )
        let s2 = makeSession(
            sessionID: "s2",
            cwd: "/repo",
            branch: "main",
            filesTouched: 2,
            taskPhase: .inProgress
        )
        let provider = MockEvidenceProvider(sessions: [s1, s2])
        let store = makeStore(directory: dir, providers: [provider])

        await store.performScan()

        let pkg = store.evidence(for: ref("s1"))
        let related = pkg.items.first(where: { $0.category == .relatedSessions })
        XCTAssertNotNil(related, "two sessions on same cwd+branch must surface a relation")
        XCTAssertEqual(related?.lines.count, 1)
        XCTAssertTrue(
            related?.lines.first?.contains("同分支") == true,
            "relation type must render localized via composer"
        )
    }

    // MARK: - Audit decisions still hold via wiring

    func testWiringRespectsUnknownTaskPhaseOmission() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let session = makeSession(
            sessionID: "s1",
            cwd: "/repo",
            taskPhase: .unknown,
            lastProgress: "x"
        )
        let provider = MockEvidenceProvider(sessions: [session])
        let store = makeStore(directory: dir, providers: [provider])
        await store.performScan()

        let pkg = store.evidence(for: ref("s1"))
        XCTAssertNil(
            pkg.items.first(where: { $0.category == .currentPhase }),
            ".unknown taskPhase must omit currentPhase even through the wiring path"
        )
    }

    func testWiringRespectsRecentFilesDegradedCount() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let session = makeSession(sessionID: "s1", filesTouched: 7)
        let provider = MockEvidenceProvider(sessions: [session])
        let store = makeStore(directory: dir, providers: [provider])
        await store.performScan()

        let pkg = store.evidence(for: ref("s1"))
        let recent = pkg.items.first(where: { $0.category == .recentFiles })
        XCTAssertEqual(recent?.lines, ["7 个文件被修改"])
    }
}
