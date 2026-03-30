import XCTest
@testable import ClaudeSessionHubLib

private final class MockProvider: AgentProvider, @unchecked Sendable {
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

final class ScanCoordinatorXCTests: XCTestCase {

    private func makeSession(providerID: String, sessionID: String, title: String = "Test") -> SessionSummary {
        SessionSummary(
            ref: SessionRef(providerID: providerID, sessionID: sessionID),
            title: title, currentTaskSummary: nil,
            runtimeState: .active, taskPhase: .inProgress,
            cwd: "/Users/test/project", branch: "main",
            turnCount: 5, filesTouched: 2, recentErrorCount: 0,
            createdAt: Date(), lastActiveAt: Date(),
            contextUsage: nil
        )
    }

    func testDeduplicatesByProviderAndSessionID() async {
        let s1 = makeSession(providerID: "claude", sessionID: "abc")
        let s2 = makeSession(providerID: "claude", sessionID: "abc")
        let provider = MockProvider(providerID: "claude", sessions: [s1, s2])
        let coordinator = ScanCoordinator(providers: [provider])
        let results = await coordinator.scan()
        XCTAssertEqual(results.count, 1, "duplicate sessionID from same provider should be deduped")
    }

    func testMultipleProviders() async {
        let s1 = makeSession(providerID: "claude", sessionID: "abc")
        let s2 = makeSession(providerID: "codex", sessionID: "abc")
        let p1 = MockProvider(providerID: "claude", sessions: [s1])
        let p2 = MockProvider(providerID: "codex", sessions: [s2])
        let coordinator = ScanCoordinator(providers: [p1, p2])
        let results = await coordinator.scan()
        XCTAssertEqual(results.count, 2, "same sessionID from different providers should both be kept")
    }

    func testEmptyProviders() async {
        let coordinator = ScanCoordinator(providers: [])
        let results = await coordinator.scan()
        XCTAssertTrue(results.isEmpty, "no providers should produce empty results")
    }

    func testLastScanTimeUpdated() async {
        let coordinator = ScanCoordinator(providers: [])
        let timeBefore = await coordinator.lastScanTime
        XCTAssertNil(timeBefore, "lastScanTime should be nil before scan")
        _ = await coordinator.scan()
        let timeAfter = await coordinator.lastScanTime
        XCTAssertNotNil(timeAfter, "lastScanTime should be non-nil after scan")
    }

    func testDisplayNameFromCwd() {
        let name = ProjectNameResolver.displayName(for: "/Users/test/OACP")
        XCTAssertEqual(name, "OACP", "displayName should extract last path component")
    }

    func testResolveCollisions() {
        let cwds = ["/Users/alice/project", "/Users/bob/project", "/Users/alice/other"]
        let resolved = ProjectNameResolver.resolveCollisions(cwds)
        XCTAssertEqual(resolved["/Users/alice/project"], "project (alice)", "collision should include parent")
        XCTAssertEqual(resolved["/Users/bob/project"], "project (bob)", "collision should include parent")
        XCTAssertEqual(resolved["/Users/alice/other"], "other", "no collision should be plain basename")
    }
}
