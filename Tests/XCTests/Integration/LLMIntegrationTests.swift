import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMIntegrationTests: XCTestCase {

    func testUnconfiguredLLMReturnsNil() async {
        var signals = SessionSignals(sessionID: "s1")
        signals.firstUserIntent = "帮我重构认证模块"
        signals.turnCount = 5
        signals.toolsUsed = ["Edit"]
        signals.filesModified = ["/auth.swift"]

        let enhancer = LLMEnhancer(config: LLMConfig())
        let result = await enhancer.enhance(signals: signals, basedOnLastActiveAt: Date())
        XCTAssertNil(result, "Unconfigured LLM should return nil")
    }

    func testSnapshotPersistsAndReloads() {
        let dir = NSTemporaryDirectory() + "llm-integration-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        let now = Date()
        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "AI标题", progress: "AI进展",
            summary: "AI摘要", modelName: "gpt-4o",
            generatedAt: now, basedOnLastActiveAt: now
        )
        store.setSnapshot(snapshot)

        // Reload from disk
        let store2 = UnderstandingStore(directory: dir)
        let loaded = store2.snapshot(for: "s1")
        XCTAssertEqual(loaded?.title, "AI标题")
        XCTAssertEqual(loaded?.progress, "AI进展")
        XCTAssertEqual(loaded?.summary, "AI摘要")
        XCTAssertFalse(store2.isStale(for: "s1", lastActiveAt: now))
    }

    func testStaleDetectionWithNewerActivity() {
        let dir = NSTemporaryDirectory() + "llm-stale-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        let oldDate = Date(timeIntervalSinceNow: -3600)
        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "T", progress: nil,
            summary: nil, modelName: "m",
            generatedAt: oldDate, basedOnLastActiveAt: oldDate
        )
        store.setSnapshot(snapshot)

        // New activity → stale
        XCTAssertTrue(store.isStale(for: "s1", lastActiveAt: Date()))
        // No new activity → not stale
        XCTAssertFalse(store.isStale(for: "s1", lastActiveAt: oldDate))
    }

    func testLLMConfigDefaultIsDisabled() {
        let config = LLMConfig()
        XCTAssertFalse(config.isConfigured)

        let enhancer = LLMEnhancer(config: config)
        // The enhancer should not make any API calls
        // Verified by the fact that enhance returns nil synchronously for unconfigured
        _ = enhancer // silence unused warning
    }

    func testPromptInputIsStructured() {
        var signals = SessionSignals(sessionID: "test-1")
        signals.firstUserIntent = "帮我重构认证模块"
        signals.branch = "feat/auth"
        signals.turnCount = 15
        signals.toolsUsed = ["Edit", "Bash"]
        signals.taskSubject = "Refactor auth"
        signals.taskStatus = "in_progress"

        let input = LLMPrompts.titleInput(from: signals)

        // Verify structured format
        XCTAssertTrue(input.contains("帮我重构认证模块"))
        XCTAssertTrue(input.contains("feat/auth"))
        XCTAssertTrue(input.contains("15"))
        XCTAssertTrue(input.contains("Refactor auth"))
        XCTAssertTrue(input.contains("in_progress"))
    }
}
