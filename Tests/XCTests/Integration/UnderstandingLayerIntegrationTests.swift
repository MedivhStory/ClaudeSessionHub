import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class UnderstandingLayerIntegrationTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "integration-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testEndToEndSmartTitleGeneration() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        // Setup: JSONL session
        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let jsonl = [
            #"{"type":"system","timestamp":"2026-03-01T10:00:00Z","cwd":"/test","gitBranch":"feat/auth","entrypoint":"new"}"#,
            #"{"type":"user","message":{"role":"user","content":"帮我重构认证中间件"},"timestamp":"2026-03-01T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/test/auth.swift","old_string":"a","new_string":"b"}}],"usage":{"input_tokens":100,"output_tokens":50}},"timestamp":"2026-03-01T10:00:02Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"认证中间件已重构完成。接下来需要补充单元测试。"}],"usage":{"input_tokens":200,"output_tokens":80}},"timestamp":"2026-03-01T10:00:03Z"}"#
        ].joined(separator: "\n")
        try jsonl.write(toFile: projectDir + "/sess-int.jsonl", atomically: true, encoding: .utf8)

        // Setup: history.jsonl
        let history = #"{"display":"帮我重构认证中间件","timestamp":1775536107472,"project":"/test","sessionId":"sess-int"}"#
        try history.write(toFile: base + "/history.jsonl", atomically: true, encoding: .utf8)

        // Setup: tasks
        let tasksDir = base + "/tasks/sess-int"
        try FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let task: [String: Any] = ["id": "1", "subject": "Refactor auth middleware", "status": "in_progress", "description": ""]
        try JSONSerialization.data(withJSONObject: task)
            .write(to: URL(fileURLWithPath: tasksDir + "/1.json"))

        // Execute: extract signals
        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "sess-int")
        var signals = try await provider.extractSignals(for: ref)

        // Enrich
        let extractor = SignalExtractor(baseDirectory: base)
        signals = extractor.enrich(signals)

        // Verify signals populated from all sources
        XCTAssertFalse(signals.historyDisplayTexts.isEmpty, "history.jsonl should be read")
        XCTAssertEqual(signals.taskSubject, "Refactor auth middleware")
        XCTAssertEqual(signals.taskStatus, "in_progress")
        XCTAssertTrue(signals.toolsUsed.contains("Edit"))
        XCTAssertTrue(signals.filesModified.contains("/test/auth.swift"))

        // Title generation
        let strategy = RuleTitleStrategy()
        XCTAssertTrue(strategy.shouldGenerateFirstTitle(for: signals), "Gate should pass: has turns + tool usage")

        let title = strategy.generateTitle(from: signals)
        XCTAssertTrue(title.text.contains("重构认证中间件") || title.text.contains("帮我重构"), "Title should contain user intent")
        XCTAssertEqual(title.source, .rule)

        // Progress extraction
        let progress = strategy.extractLastProgress(from: signals)
        XCTAssertNotNil(progress)

        // Search should find this session
        let score = SearchScorer.score(
            query: "认证",
            title: "sess-int",
            smartTitle: title.text,
            taskSummary: nil, progress: progress, userNote: nil,
            branch: "feat/auth", cwd: "/test", sessionID: "sess-int",
            historyTexts: signals.historyDisplayTexts
        )
        XCTAssertTrue(score > 0, "Search for '认证' should match")

        // Search evidence
        let evidence = SearchScorer.matchEvidence(
            query: "认证",
            title: "sess-int",
            smartTitle: title.text,
            taskSummary: nil, progress: progress, userNote: nil,
            branch: "feat/auth", cwd: "/test", sessionID: "sess-int",
            historyTexts: signals.historyDisplayTexts
        )
        XCTAssertFalse(evidence.isEmpty, "Should have match evidence")
    }

    func testGateRejectsEmptySession() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        // Session with only a system entry — no user turns, no progress
        let jsonl = #"{"type":"system","timestamp":"2026-03-01T10:00:00Z","cwd":"/test"}"#
        try jsonl.write(toFile: projectDir + "/empty-sess.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "empty-sess")
        let signals = try await provider.extractSignals(for: ref)

        let strategy = RuleTitleStrategy()
        XCTAssertFalse(strategy.shouldGenerateFirstTitle(for: signals), "Gate should reject: no turns, no progress")
    }
}
