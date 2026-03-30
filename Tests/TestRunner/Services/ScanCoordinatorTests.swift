import Foundation
@testable import ClaudeSessionHubLib

final class MockProvider: AgentProvider, @unchecked Sendable {
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

enum ScanCoordinatorTests {
    private static func makeSession(providerID: String, sessionID: String, title: String = "Test") -> SessionSummary {
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

    static func run() {
        print("--- ScanCoordinatorTests ---")
        testDeduplicatesByProviderAndSessionID()
        testMultipleProviders()
        testEmptyProviders()
        testLastScanTimeUpdated()
        testDisplayNameFromCwd()
        testResolveCollisions()
    }

    // Test 1: same provider, duplicate sessionID → deduped
    private static func testDeduplicatesByProviderAndSessionID() {
        let s1 = makeSession(providerID: "claude", sessionID: "abc")
        let s2 = makeSession(providerID: "claude", sessionID: "abc")
        let provider = MockProvider(providerID: "claude", sessions: [s1, s2])
        let coordinator = ScanCoordinator(providers: [provider])
        let results = runAsync { await coordinator.scan() }
        assertEqual(results.count, 1, "duplicate sessionID from same provider should be deduped")
    }

    // Test 2: different providers with same sessionID → NOT deduped (both kept)
    private static func testMultipleProviders() {
        let s1 = makeSession(providerID: "claude", sessionID: "abc")
        let s2 = makeSession(providerID: "codex", sessionID: "abc")
        let p1 = MockProvider(providerID: "claude", sessions: [s1])
        let p2 = MockProvider(providerID: "codex", sessions: [s2])
        let coordinator = ScanCoordinator(providers: [p1, p2])
        let results = runAsync { await coordinator.scan() }
        assertEqual(results.count, 2, "same sessionID from different providers should both be kept")
    }

    // Test 3: no providers → empty results
    private static func testEmptyProviders() {
        let coordinator = ScanCoordinator(providers: [])
        let results = runAsync { await coordinator.scan() }
        assertEqual(results.count, 0, "no providers should produce empty results")
    }

    // Test 4: after scan, lastScanTime should be non-nil
    private static func testLastScanTimeUpdated() {
        let coordinator = ScanCoordinator(providers: [])
        let timeBefore = runAsync { await coordinator.lastScanTime }
        check(timeBefore == nil, "lastScanTime should be nil before scan")
        _ = runAsync { await coordinator.scan() }
        let timeAfter = runAsync { await coordinator.lastScanTime }
        check(timeAfter != nil, "lastScanTime should be non-nil after scan")
    }

    // Test 5: ProjectNameResolver.displayName
    private static func testDisplayNameFromCwd() {
        let name = ProjectNameResolver.displayName(for: "/Users/test/OACP")
        assertEqual(name, "OACP", "displayName should extract last path component")
    }

    // Test 6: ProjectNameResolver.resolveCollisions
    private static func testResolveCollisions() {
        let cwds = ["/Users/alice/project", "/Users/bob/project", "/Users/alice/other"]
        let resolved = ProjectNameResolver.resolveCollisions(cwds)
        assertEqual(resolved["/Users/alice/project"], "project (alice)", "collision should include parent")
        assertEqual(resolved["/Users/bob/project"], "project (bob)", "collision should include parent")
        assertEqual(resolved["/Users/alice/other"], "other", "no collision should be plain basename")
    }

    // MARK: - Async helpers

    private static func runAsync<T>(_ block: @escaping () async throws -> T) rethrows -> T {
        var result: Result<T, Error>!
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let value = try await block()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            sem.signal()
        }
        sem.wait()
        switch result! {
        case .success(let value): return value
        case .failure(let error):
            fatalError("Async block threw: \(error)")
        }
    }

    private static func runAsync<T>(_ block: @escaping () async -> T) -> T {
        var value: T!
        let sem = DispatchSemaphore(value: 0)
        Task {
            value = await block()
            sem.signal()
        }
        sem.wait()
        return value
    }
}
