import XCTest
@testable import ClaudeSessionHubLib

final class ClaudeProviderXCTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "claude-xctest-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func buildTestJSONL() -> String {
        let lines: [String] = [
            """
            {"type":"system","timestamp":"2026-03-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"feature/session-hub"}
            """,
            """
            {"type":"user","isMeta":true,"message":{"role":"user","content":"/resume"},"timestamp":"2026-03-01T10:00:01Z"}
            """,
            """
            {"type":"user","message":{"role":"user","content":"帮我重构这个模块的代码结构"},"timestamp":"2026-03-01T10:00:02Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/main.swift","old_string":"foo","new_string":"bar"}}],"usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":500,"cache_read_input_tokens":300}},"timestamp":"2026-03-01T10:00:03Z"}
            """,
            """
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool1","content":"Error: file not found","is_error":true}]},"timestamp":"2026-03-01T10:00:04Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/test/project/new.swift","content":"hello"}}],"usage":{"input_tokens":1200,"output_tokens":300,"cache_creation_input_tokens":600,"cache_read_input_tokens":400}},"timestamp":"2026-03-01T10:00:05Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/main.swift","old_string":"bar","new_string":"baz"}}]},"timestamp":"2026-03-01T10:00:06Z"}
            """,
            """
            {"type":"user","message":{"role":"user","content":"现在请检查测试是否通过"},"timestamp":"2026-03-01T10:00:07Z"}
            """
        ]
        return lines.joined(separator: "\n")
    }

    func testDiscoverSessionsFindsJSONL() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/abc123.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.ref.sessionID, "abc123")
    }

    func testTitleSkipsMetaExtractsVerbPattern() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/sess1.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()

        XCTAssertTrue(sessions.first?.title.contains("帮我重构") ?? false)
    }

    func testCwdAndBranchExtracted() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/sess2.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.first?.cwd, "/Users/test/project")
        XCTAssertEqual(sessions.first?.branch, "feature/session-hub")
    }

    func testContextUsageIncludesCacheTokens() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/sess4.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()
        let ctx = sessions.first?.contextUsage

        XCTAssertEqual(ctx?.inputTokens, 1200)
        XCTAssertEqual(ctx?.cacheCreationTokens, 600)
        XCTAssertEqual(ctx?.cacheReadTokens, 400)
        XCTAssertEqual(ctx?.promptContext, 2200)
    }

    func testFilesTouchedCountsUnique() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/sess5.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.first?.filesTouched, 2)
    }

    func testRecentErrorCountFromToolResult() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/sess6.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.first?.recentErrorCount, 1)
    }

    func testExcludesSubagentDirectories() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: projectDir + "/normal.jsonl", atomically: true, encoding: .utf8)

        let subagentDir = base + "/projects/subagents"
        try FileManager.default.createDirectory(atPath: subagentDir, withIntermediateDirectories: true)
        try buildTestJSONL().write(toFile: subagentDir + "/sub1.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.ref.sessionID, "normal")
    }

    func testMakeResumeTarget() throws {
        let provider = ClaudeProvider(baseDirectory: "/tmp/fake")
        let ref = SessionRef(providerID: "claude", sessionID: "abc123")
        let target = try provider.makeResumeTarget(for: ref)

        XCTAssertEqual(target.executable, "claude")
        XCTAssertEqual(target.arguments, ["-r", "abc123"])
        XCTAssertEqual(target.displayCommand, "claude -r abc123")
    }

    func testRefreshRuntimeStateDeadForNonExistentPID() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let sessionsDir = base + "/sessions"
        try FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        let metadata: [String: Any] = ["pid": 99999999]
        let data = try JSONSerialization.data(withJSONObject: metadata)
        try data.write(to: URL(fileURLWithPath: sessionsDir + "/test-session.json"))

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "test-session")
        let states = await provider.refreshRuntimeState(for: [ref])

        if case .dead = states[ref] {
            // expected
        } else {
            XCTFail("Expected .dead for non-existent PID")
        }
    }
}
