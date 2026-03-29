import Foundation
@testable import ClaudeSessionHubLib

enum ClaudeProviderTests {
    static func run() {
        print("── ClaudeProviderTests ──")
        testDiscoverSessionsFindsJSONL()
        testTitleSkipsMetaExtractsVerbPattern()
        testCwdAndBranchExtracted()
        testCurrentTaskSummarySkipsMetaAndToolResults()
        testCurrentTaskSummarySkipsInternalCommandNoise()
        testContextUsageIncludesCacheTokens()
        testFilesTouchedCountsUnique()
        testRecentErrorCountFromToolResult()
        testExcludesSubagentDirectories()
        testMakeResumeTarget()
        testRefreshRuntimeStateDeadForNonExistentPID()
    }

    // MARK: - Helpers

    private static func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "claude-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Build a realistic JSONL file content for testing
    private static func buildTestJSONL() -> String {
        let lines: [String] = [
            // Entry 1: system/init with timestamp and cwd
            """
            {"type":"system","timestamp":"2026-03-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"feature/session-hub"}
            """,
            // Entry 2: /resume meta user entry (should be skipped for title/turnCount)
            """
            {"type":"user","isMeta":true,"message":{"role":"user","content":"/resume"},"timestamp":"2026-03-01T10:00:01Z"}
            """,
            // Entry 3: normal user with Chinese verb pattern -> title candidate
            """
            {"type":"user","message":{"role":"user","content":"帮我重构这个模块的代码结构"},"timestamp":"2026-03-01T10:00:02Z"}
            """,
            // Entry 4: assistant with tool_use (Edit) and usage
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/main.swift","old_string":"foo","new_string":"bar"}}],"usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":500,"cache_read_input_tokens":300}},"timestamp":"2026-03-01T10:00:03Z"}
            """,
            // Entry 5: user with tool_result containing is_error true
            """
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool1","content":"Error: file not found","is_error":true}]},"timestamp":"2026-03-01T10:00:04Z"}
            """,
            // Entry 6: assistant with tool_use (Write)
            """
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/test/project/new.swift","content":"hello"}}],"usage":{"input_tokens":1200,"output_tokens":300,"cache_creation_input_tokens":600,"cache_read_input_tokens":400}},"timestamp":"2026-03-01T10:00:05Z"}
            """,
            // Entry 7: assistant with Edit on same file as entry 4 (should not double count)
            """
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/main.swift","old_string":"bar","new_string":"baz"}}]},"timestamp":"2026-03-01T10:00:06Z"}
            """,
            // Entry 8: final normal user entry -> currentTaskSummary
            """
            {"type":"user","message":{"role":"user","content":"现在请检查测试是否通过"},"timestamp":"2026-03-01T10:00:07Z"}
            """
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - Tests

    static func testDiscoverSessionsFindsJSONL() {
        let base = createTempDir()
        defer { cleanup(base) }

        // Create projects/<project>/session.jsonl
        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let jsonlPath = projectDir + "/abc123.jsonl"
        try! buildTestJSONL().write(toFile: jsonlPath, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        check(sessions.count >= 1, "should discover at least 1 session, got \(sessions.count)")
        if let first = sessions.first {
            assertEqual(first.ref.sessionID, "abc123", "session ID from filename")
            assertEqual(first.ref.providerID, "claude")
        }
    }

    static func testTitleSkipsMetaExtractsVerbPattern() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/sess1.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        check(!sessions.isEmpty, "should have sessions")
        if let s = sessions.first {
            // Should pick the Chinese verb pattern title, not the /resume meta entry
            check(s.title.contains("帮我重构"), "title should contain Chinese verb, got: \(s.title)")
            check(!s.title.contains("/resume"), "title should not be /resume meta")
        }
    }

    static func testCwdAndBranchExtracted() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/sess2.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        if let s = sessions.first {
            assertEqual(s.cwd, "/Users/test/project", "cwd extracted")
            assertEqual(s.branch, "feature/session-hub", "branch extracted")
        } else {
            check(false, "no sessions found")
        }
    }

    static func testCurrentTaskSummarySkipsMetaAndToolResults() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/sess3.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        if let s = sessions.first {
            // Should be last normal user msg with string content (entry 8), not tool_result (entry 5) or meta (entry 2)
            check(s.currentTaskSummary != nil, "currentTaskSummary should exist")
            if let summary = s.currentTaskSummary {
                check(summary.contains("检查测试"), "should be final user msg, got: \(summary)")
            }
        } else {
            check(false, "no sessions")
        }
    }

    static func testCurrentTaskSummarySkipsInternalCommandNoise() {
        let base = createTempDir()
        defer { cleanup(base) }

        // JSONL where last user messages are internal noise, then a real message
        let lines = [
            "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"帮我修复 bug\"},\"timestamp\":\"2026-03-01T10:00:00Z\",\"cwd\":\"/tmp\"}",
            "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<local-command-stdout>Login interrupted</local-command-stdout>\"},\"timestamp\":\"2026-03-01T10:00:01Z\"}",
            "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>/login</command-name>\\n            <command-message>login</command-message>\"},\"timestamp\":\"2026-03-01T10:00:02Z\"}",
            "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"/resume\"},\"timestamp\":\"2026-03-01T10:00:03Z\"}"
        ]
        let projectDir = base + "/projects/proj"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! lines.joined(separator: "\n").write(toFile: projectDir + "/noise-test.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        if let s = sessions.first {
            // Should skip all noise and return "帮我修复 bug"
            check(s.currentTaskSummary != nil, "should find summary past noise")
            if let summary = s.currentTaskSummary {
                check(summary.contains("修复 bug"), "should be human intent, got: \(summary)")
                check(!summary.contains("local-command"), "should not contain noise")
                check(!summary.contains("/resume"), "should not contain /resume")
            }
        } else {
            check(false, "no sessions")
        }
    }

    static func testContextUsageIncludesCacheTokens() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/sess4.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        if let s = sessions.first, let ctx = s.contextUsage {
            // Last assistant with usage is entry 6: input=1200, cache_creation=600, cache_read=400
            assertEqual(ctx.inputTokens, 1200, "inputTokens")
            assertEqual(ctx.cacheCreationTokens, 600, "cacheCreationTokens")
            assertEqual(ctx.cacheReadTokens, 400, "cacheReadTokens")
            assertEqual(ctx.promptContext, 2200, "promptContext = 1200+600+400")
            assertEqual(ctx.limit, 200_000, "sonnet limit")
        } else {
            check(false, "no contextUsage")
        }
    }

    static func testFilesTouchedCountsUnique() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/sess5.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        if let s = sessions.first {
            // main.swift (Edit x2 = unique 1) + new.swift (Write) = 2
            assertEqual(s.filesTouched, 2, "unique files touched")
        } else {
            check(false, "no sessions")
        }
    }

    static func testRecentErrorCountFromToolResult() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/sess6.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        if let s = sessions.first {
            assertEqual(s.recentErrorCount, 1, "1 tool_result with is_error")
        } else {
            check(false, "no sessions")
        }
    }

    static func testExcludesSubagentDirectories() {
        let base = createTempDir()
        defer { cleanup(base) }

        // Create a normal session
        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: projectDir + "/normal.jsonl", atomically: true, encoding: .utf8)

        // Create a subagents directory (should be excluded)
        let subagentDir = base + "/projects/subagents"
        try! FileManager.default.createDirectory(atPath: subagentDir, withIntermediateDirectories: true)
        try! buildTestJSONL().write(toFile: subagentDir + "/sub1.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try! runAsync { try await provider.discoverSessions() }

        assertEqual(sessions.count, 1, "should only find 1 session, not subagent")
        if let s = sessions.first {
            assertEqual(s.ref.sessionID, "normal")
        }
    }

    static func testMakeResumeTarget() {
        let provider = ClaudeProvider(baseDirectory: "/tmp/fake")
        let ref = SessionRef(providerID: "claude", sessionID: "abc123")
        let target = try! provider.makeResumeTarget(for: ref)

        assertEqual(target.executable, "claude")
        assertEqual(target.arguments, ["-r", "abc123"])
        assertEqual(target.displayCommand, "claude -r abc123")
    }

    static func testRefreshRuntimeStateDeadForNonExistentPID() {
        let base = createTempDir()
        defer { cleanup(base) }

        // Create sessions dir with a <pid>.json metadata file (Claude's actual scheme)
        let sessionsDir = base + "/sessions"
        try! FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        let metadata: [String: Any] = ["pid": 99999999, "sessionId": "test-session", "cwd": "/tmp", "startedAt": 1772645500000]
        let data = try! JSONSerialization.data(withJSONObject: metadata)
        try! data.write(to: URL(fileURLWithPath: sessionsDir + "/99999999.json"))

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "test-session")
        let states = runAsync { await provider.refreshRuntimeState(for: [ref]) }

        if let state = states[ref] {
            switch state {
            case .dead:
                check(true, "non-existent PID -> dead")
            case .alive:
                check(false, "should be dead for fake PID")
            }
        } else {
            check(false, "should have state for ref")
        }
    }

    // MARK: - Async helper

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
            // Re-throw by crashing since we can't properly rethrow here
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
