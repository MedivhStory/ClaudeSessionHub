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
        testLoadSessionDetailTotalErrorCount()
        testLoadSessionDetailCumulativeTokens()
        testLoadSessionDetailRecentFiles()
        testLoadSessionDetailModelInfo()
        testLoadSessionDetailNextStep()
        testExtractEnhanceInputsRecoversIntentOutsideWindow()
        testExtractEnhanceInputsPopulatesJsonlHistoryFallback()
        testExtractEnhanceInputsLabelsRawTurnsByPosition()
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

    /// Build test JSONL with additional entries for detail testing (nextStep, extra errors, more tokens)
    private static func buildDetailTestJSONL() -> String {
        let lines: [String] = [
            // Entry 1: system/init
            """
            {"type":"system","timestamp":"2026-03-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"feature/detail"}
            """,
            // Entry 2: normal user
            """
            {"type":"user","message":{"role":"user","content":"帮我重构这个模块"},"timestamp":"2026-03-01T10:00:01Z"}
            """,
            // Entry 3: assistant with Edit + usage
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/a.swift","old_string":"x","new_string":"y"}}],"usage":{"input_tokens":500,"output_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":100}},"timestamp":"2026-03-01T10:00:02Z"}
            """,
            // Entry 4: user with error tool_result
            """
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"Error: not found","is_error":true}]},"timestamp":"2026-03-01T10:00:03Z"}
            """,
            // Entry 5: assistant with Write + usage
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/test/project/b.swift","content":"new"}}],"usage":{"input_tokens":600,"output_tokens":150,"cache_creation_input_tokens":250,"cache_read_input_tokens":120}},"timestamp":"2026-03-01T10:00:04Z"}
            """,
            // Entry 6: user with another error
            """
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"compile error","is_error":true}]},"timestamp":"2026-03-01T10:00:05Z"}
            """,
            // Entry 7: assistant with Edit on new file + usage
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/c.swift","old_string":"old","new_string":"new"}}],"usage":{"input_tokens":700,"output_tokens":200,"cache_creation_input_tokens":300,"cache_read_input_tokens":150}},"timestamp":"2026-03-01T10:00:06Z"}
            """,
            // Entry 8: assistant with forward-looking text (nextStep)
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"代码已修改完成。接下来需要运行测试确认所有功能正常工作。"}],"usage":{"input_tokens":800,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-01T10:00:07Z"}
            """,
            // Entry 9: final user
            """
            {"type":"user","message":{"role":"user","content":"好的，请继续"},"timestamp":"2026-03-01T10:00:08Z"}
            """
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - Detail Tests

    static func testLoadSessionDetailTotalErrorCount() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildDetailTestJSONL().write(toFile: projectDir + "/detail1.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail1")
        let detail = try! runAsync { try await provider.loadSessionDetail(for: ref) }

        // 2 tool_result entries with is_error:true (entries 4 and 6)
        assertEqual(detail.totalErrorCount, 2, "totalErrorCount should be 2")
    }

    static func testLoadSessionDetailCumulativeTokens() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildDetailTestJSONL().write(toFile: projectDir + "/detail2.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail2")
        let detail = try! runAsync { try await provider.loadSessionDetail(for: ref) }

        check(detail.cumulativeTokens != nil, "cumulativeTokens should not be nil")
        if let tokens = detail.cumulativeTokens {
            // input: 500+600+700+800 = 2600
            assertEqual(tokens.inputTokens, 2600, "cumulative inputTokens")
            // output: 100+150+200+50 = 500
            assertEqual(tokens.outputTokens, 500, "cumulative outputTokens")
            // cacheRead: 100+120+150+0 = 370
            assertEqual(tokens.cacheReadTokens, 370, "cumulative cacheReadTokens")
            // cacheWrite: 200+250+300+0 = 750
            assertEqual(tokens.cacheWriteTokens, 750, "cumulative cacheWriteTokens")
            // total: 2600+500+370+750 = 4220
            assertEqual(tokens.totalTokens, 4220, "cumulative totalTokens")
        }
    }

    static func testLoadSessionDetailRecentFiles() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildDetailTestJSONL().write(toFile: projectDir + "/detail3.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail3")
        let detail = try! runAsync { try await provider.loadSessionDetail(for: ref) }

        // Files: a.swift (Edit), b.swift (Write), c.swift (Edit) = 3 unique, in order
        assertEqual(detail.recentFiles.count, 3, "recentFiles count")
        check(detail.recentFiles.contains("/Users/test/project/a.swift"), "should contain a.swift")
        check(detail.recentFiles.contains("/Users/test/project/b.swift"), "should contain b.swift")
        check(detail.recentFiles.contains("/Users/test/project/c.swift"), "should contain c.swift")
    }

    static func testLoadSessionDetailModelInfo() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildDetailTestJSONL().write(toFile: projectDir + "/detail4.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail4")
        let detail = try! runAsync { try await provider.loadSessionDetail(for: ref) }

        check(detail.modelInfo != nil, "modelInfo should not be nil")
        if let model = detail.modelInfo {
            assertEqual(model.modelName, "claude-sonnet-4-20250514", "model name")
            assertEqual(model.contextLimit, 200_000, "sonnet context limit")
        }
    }

    static func testLoadSessionDetailNextStep() {
        let base = createTempDir()
        defer { cleanup(base) }

        let projectDir = base + "/projects/myproject"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try! buildDetailTestJSONL().write(toFile: projectDir + "/detail5.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail5")
        let detail = try! runAsync { try await provider.loadSessionDetail(for: ref) }

        check(detail.nextStep != nil, "nextStep should not be nil")
        if let nextStep = detail.nextStep {
            check(nextStep.contains("接下来"), "nextStep should contain forward-looking pattern, got: \(nextStep)")
            check(nextStep.count <= 120, "nextStep should be <= 120 chars")
        }
    }

    // MARK: - v0.2.8.1 extractEnhanceInputs regression tests

    /// Build a jsonl where the first 15 entries are slash-command noise and
    /// the last 60 entries are tool_result-heavy. The REAL first and last
    /// user text turns sit at lines 16 and 80 — outside the 10+50 window that
    /// `extractSignals` uses. extractEnhanceInputs must recover them via full scan.
    private static func buildTailBiasTestJSONL(sessionID: String, topic: String) -> String {
        var lines: [String] = []
        // 15 head entries: slash-command wrappers + attachments (all noise)
        for i in 0..<5 {
            lines.append("{\"type\":\"user\",\"isMeta\":true,\"message\":{\"role\":\"user\",\"content\":\"<local-command-caveat>noise \(i)</local-command-caveat>\"}}")
            lines.append("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>/model</command-name>\"}}")
            lines.append("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<local-command-stdout>Set model</local-command-stdout>\"}}")
        }
        // Entry 16: the real first user intent mentioning the topic
        lines.append("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"我在 \(topic) 平台上搭一个 workflow，帮我理清思路\"},\"cwd\":\"/Users/test/\(topic)\",\"gitBranch\":\"HEAD\"}")
        // Middle: 60 real user turns + 10 assistant turns discussing the topic
        for i in 0..<60 {
            lines.append("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"关于 \(topic) 的第 \(i) 条讨论内容，需要继续优化\"}}")
        }
        for _ in 0..<10 {
            lines.append("{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-test\",\"content\":[{\"type\":\"text\",\"text\":\"好的我理解了 \(topic) 的需求\"}]}}")
        }
        // Last 60 entries: tool_result-heavy debug tail (no qualifying user text turns)
        for i in 0..<30 {
            lines.append("{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"点击 selector.\(i) 但 innerText 仍为空\"}]}}")
            lines.append("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t\(i)\",\"content\":\"[{\\\"type\\\":\\\"text\\\",\\\"text\\\":\\\"Dragged\\\"}]\"}]}}")
        }
        // Ensure sessionId appears on at least one entry
        lines[0] = "{\"type\":\"user\",\"isMeta\":true,\"sessionId\":\"\(sessionID)\",\"message\":{\"role\":\"user\",\"content\":\"<local-command-caveat>noise 0</local-command-caveat>\"}}"
        return lines.joined(separator: "\n")
    }

    /// Bug B regression: real first/last user text turns sitting outside the
    /// cheap 10+50 window are still extracted via the full-scan path.
    static func testExtractEnhanceInputsRecoversIntentOutsideWindow() {
        let base = createTempDir()
        defer { cleanup(base) }
        let projectDir = base + "/projects/-Users-test-cozerepo"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let sid = "enhance-recover-\(UUID().uuidString.prefix(8))"
        try! buildTailBiasTestJSONL(sessionID: String(sid), topic: "coze")
            .write(toFile: projectDir + "/\(sid).jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: String(sid))
        let inputs = try! runAsync { try await provider.extractEnhanceInputs(for: ref) }

        check(inputs.signals.firstUserIntent != nil,
              "firstUserIntent must be recovered from full scan, got nil")
        if let first = inputs.signals.firstUserIntent {
            check(first.contains("coze"),
                  "firstUserIntent should mention 'coze', got: \(first)")
        }
        check(inputs.signals.lastUserIntent != nil,
              "lastUserIntent must be recovered (last real user turn before tool_result tail)")
    }

    /// Bug C regression: historyDisplayTexts is populated from jsonl when
    /// the SessionExtractor's history.jsonl has no rows.
    static func testExtractEnhanceInputsPopulatesJsonlHistoryFallback() {
        let base = createTempDir()
        defer { cleanup(base) }
        let projectDir = base + "/projects/-Users-test-cozerepo"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let sid = "enhance-history-\(UUID().uuidString.prefix(8))"
        try! buildTailBiasTestJSONL(sessionID: String(sid), topic: "coze")
            .write(toFile: projectDir + "/\(sid).jsonl", atomically: true, encoding: .utf8)
        // Deliberately do NOT create base + "/history.jsonl"

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: String(sid))
        let inputs = try! runAsync { try await provider.extractEnhanceInputs(for: ref) }

        check(!inputs.signals.historyDisplayTexts.isEmpty,
              "historyDisplayTexts should fall back to jsonl user-text stream, got empty")
        check(inputs.signals.historyCount >= 30,
              "historyCount should reflect the ~61 real user text turns in the fixture, got \(inputs.signals.historyCount)")
        // And the SignalExtractor.enrich must preserve this fallback when history.jsonl is absent
        let extractor = SignalExtractor(baseDirectory: base)
        let enriched = extractor.enrich(inputs.signals)
        check(!enriched.historyDisplayTexts.isEmpty,
              "SignalExtractor.enrich must NOT wipe jsonl-derived history when history.jsonl is empty")
    }

    /// Bug D regression: extractEnhanceInputs emits position-labeled rawTurns.
    static func testExtractEnhanceInputsLabelsRawTurnsByPosition() {
        let base = createTempDir()
        defer { cleanup(base) }
        let projectDir = base + "/projects/-Users-test-cozerepo"
        try! FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let sid = "enhance-labels-\(UUID().uuidString.prefix(8))"
        try! buildTailBiasTestJSONL(sessionID: String(sid), topic: "coze")
            .write(toFile: projectDir + "/\(sid).jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: String(sid))
        let inputs = try! runAsync { try await provider.extractEnhanceInputs(for: ref) }

        check(!inputs.rawTurns.isEmpty, "rawTurns should not be empty")
        let hasHead = inputs.rawTurns.contains { $0.hasPrefix("[首]") }
        let hasMid  = inputs.rawTurns.contains { $0.hasPrefix("[中]") }
        check(hasHead, "rawTurns must include at least one [首] labelled turn, got: \(inputs.rawTurns.map { String($0.prefix(10)) })")
        check(hasMid,  "rawTurns must include at least one [中] labelled turn, got: \(inputs.rawTurns.map { String($0.prefix(10)) })")
        // Every turn is labelled — no bare rawTurn strings
        for turn in inputs.rawTurns {
            let labelled = turn.hasPrefix("[首]") || turn.hasPrefix("[中]") || turn.hasPrefix("[末]")
            check(labelled, "every rawTurn must be position-labelled, got: \(turn.prefix(30))")
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
