import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

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

        // Claude stores metadata as sessions/<pid>.json with sessionId inside the JSON body
        let sessionsDir = base + "/sessions"
        try FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        let metadata: [String: Any] = ["pid": 99999999, "sessionId": "test-session", "cwd": "/tmp", "startedAt": 1772645500000]
        let data = try JSONSerialization.data(withJSONObject: metadata)
        try data.write(to: URL(fileURLWithPath: sessionsDir + "/99999999.json"))

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "test-session")
        let states = await provider.refreshRuntimeState(for: [ref])

        if case .dead = states[ref] {
            // expected
        } else {
            XCTFail("Expected .dead for non-existent PID")
        }
    }

    // MARK: - Detail Tests

    private func buildDetailTestJSONL() -> String {
        let lines: [String] = [
            """
            {"type":"system","timestamp":"2026-03-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"feature/detail"}
            """,
            """
            {"type":"user","message":{"role":"user","content":"帮我重构这个模块"},"timestamp":"2026-03-01T10:00:01Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/a.swift","old_string":"x","new_string":"y"}}],"usage":{"input_tokens":500,"output_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":100}},"timestamp":"2026-03-01T10:00:02Z"}
            """,
            """
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"Error: not found","is_error":true}]},"timestamp":"2026-03-01T10:00:03Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/test/project/b.swift","content":"new"}}],"usage":{"input_tokens":600,"output_tokens":150,"cache_creation_input_tokens":250,"cache_read_input_tokens":120}},"timestamp":"2026-03-01T10:00:04Z"}
            """,
            """
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"compile error","is_error":true}]},"timestamp":"2026-03-01T10:00:05Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/test/project/c.swift","old_string":"old","new_string":"new"}}],"usage":{"input_tokens":700,"output_tokens":200,"cache_creation_input_tokens":300,"cache_read_input_tokens":150}},"timestamp":"2026-03-01T10:00:06Z"}
            """,
            """
            {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"代码已修改完成。接下来需要运行测试确认所有功能正常工作。"}],"usage":{"input_tokens":800,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-01T10:00:07Z"}
            """,
            """
            {"type":"user","message":{"role":"user","content":"好的，请继续"},"timestamp":"2026-03-01T10:00:08Z"}
            """
        ]
        return lines.joined(separator: "\n")
    }

    func testLoadSessionDetailTotalErrorCount() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildDetailTestJSONL().write(toFile: projectDir + "/detail1.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail1")
        let detail = try await provider.loadSessionDetail(for: ref)

        XCTAssertEqual(detail.totalErrorCount, 2)
    }

    func testLoadSessionDetailCumulativeTokens() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildDetailTestJSONL().write(toFile: projectDir + "/detail2.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail2")
        let detail = try await provider.loadSessionDetail(for: ref)

        XCTAssertNotNil(detail.cumulativeTokens)
        XCTAssertEqual(detail.cumulativeTokens?.inputTokens, 2600)
        XCTAssertEqual(detail.cumulativeTokens?.outputTokens, 500)
        XCTAssertEqual(detail.cumulativeTokens?.cacheReadTokens, 370)
        XCTAssertEqual(detail.cumulativeTokens?.cacheWriteTokens, 750)
        XCTAssertEqual(detail.cumulativeTokens?.totalTokens, 4220)
    }

    func testLoadSessionDetailRecentFiles() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildDetailTestJSONL().write(toFile: projectDir + "/detail3.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail3")
        let detail = try await provider.loadSessionDetail(for: ref)

        XCTAssertEqual(detail.recentFiles.count, 3)
        XCTAssertTrue(detail.recentFiles.contains("/Users/test/project/a.swift"))
        XCTAssertTrue(detail.recentFiles.contains("/Users/test/project/b.swift"))
        XCTAssertTrue(detail.recentFiles.contains("/Users/test/project/c.swift"))
    }

    func testLoadSessionDetailModelInfo() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildDetailTestJSONL().write(toFile: projectDir + "/detail4.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail4")
        let detail = try await provider.loadSessionDetail(for: ref)

        XCTAssertNotNil(detail.modelInfo)
        XCTAssertEqual(detail.modelInfo?.modelName, "claude-sonnet-4-20250514")
        XCTAssertEqual(detail.modelInfo?.contextLimit, 200_000)
    }

    // MARK: - v0.2 Signal Extraction Tests

    func testEntrypointExtracted() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        let jsonl = [
            #"{"type":"system","timestamp":"2026-03-01T10:00:00Z","entrypoint":"resume"}"#,
            #"{"type":"user","message":{"role":"user","content":"继续之前的工作"},"timestamp":"2026-03-01T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"好的，继续。"}],"usage":{"input_tokens":100,"output_tokens":50}},"timestamp":"2026-03-01T10:00:02Z"}"#
        ].joined(separator: "\n")
        try jsonl.write(toFile: projectDir + "/ep-test.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.first?.entrypoint, "resume")
    }

    func testExtractSessionSignals() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        // Reuse existing buildTestJSONL() helper
        try buildTestJSONL().write(toFile: projectDir + "/sig-test.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "sig-test")
        let signals = try await provider.extractSignals(for: ref)

        XCTAssertEqual(signals.sessionID, "sig-test")
        XCTAssertNotNil(signals.firstUserIntent)
        XCTAssertTrue(signals.firstUserIntent?.contains("帮我重构") ?? false)
        XCTAssertNotNil(signals.lastUserIntent)
        XCTAssertTrue(signals.toolsUsed.contains("Edit"))
        XCTAssertTrue(signals.toolsUsed.contains("Write"))
        XCTAssertFalse(signals.filesModified.isEmpty)
    }

    func testLoadSessionDetailNextStep() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try buildDetailTestJSONL().write(toFile: projectDir + "/detail5.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "detail5")
        let detail = try await provider.loadSessionDetail(for: ref)

        XCTAssertNotNil(detail.nextStep)
        XCTAssertTrue(detail.nextStep?.contains("接下来") ?? false)
        XCTAssertTrue((detail.nextStep?.count ?? 999) <= 120)
    }

    // MARK: - v0.2.8 VersionMentions Integration Tests

    func test_extractSignals_populatesVersionMentions_fromFirstUserIntent() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        let jsonl = [
            #"{"type":"system","timestamp":"2026-04-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"main"}"#,
            #"{"type":"user","message":{"role":"user","content":"I am working on v0.2.5 release features"},"timestamp":"2026-04-01T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Got it, I will help with the v0.2.5 work."}],"usage":{"input_tokens":100,"output_tokens":50}},"timestamp":"2026-04-01T10:00:02Z"}"#
        ].joined(separator: "\n")
        try jsonl.write(toFile: projectDir + "/vm-intent.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "vm-intent")
        let signals = try await provider.extractSignals(for: ref)

        XCTAssertTrue(signals.versionMentions.contains { $0.normalized == "0.2.5" })
        let v025 = signals.versionMentions.first(where: { $0.normalized == "0.2.5" })!
        XCTAssertEqual(v025.selectedSource.kind, .firstUserIntent)
        XCTAssertNil(v025.selectedSource.index)
    }

    func test_extractSignals_populatesVersionMentions_fromLastUserIntent() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        let jsonl = [
            #"{"type":"system","timestamp":"2026-04-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"main"}"#,
            #"{"type":"user","message":{"role":"user","content":"let us start with the basics"},"timestamp":"2026-04-01T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sure."}],"usage":{"input_tokens":100,"output_tokens":10}},"timestamp":"2026-04-01T10:00:02Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"now please implement the v0.3.0 upgrade path"},"timestamp":"2026-04-01T10:00:03Z"}"#
        ].joined(separator: "\n")
        try jsonl.write(toFile: projectDir + "/vm-lastintent.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "vm-lastintent")
        let signals = try await provider.extractSignals(for: ref)

        XCTAssertFalse(signals.versionMentions.isEmpty)
        XCTAssertTrue(signals.versionMentions.contains { $0.normalized == "0.3.0" })
        XCTAssertTrue(signals.versionMentions.first(where: { $0.normalized == "0.3.0" })!.occurrenceCount >= 1)
    }

    func test_extractSignals_emptySession_emptyVersionMentions() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        let jsonl = [
            #"{"type":"system","timestamp":"2026-04-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"main"}"#,
            #"{"type":"user","message":{"role":"user","content":"请帮我修复这个bug"},"timestamp":"2026-04-01T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"好的，我来修复。"}],"usage":{"input_tokens":50,"output_tokens":20}},"timestamp":"2026-04-01T10:00:02Z"}"#
        ].joined(separator: "\n")
        try jsonl.write(toFile: projectDir + "/vm-empty.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "vm-empty")
        let signals = try await provider.extractSignals(for: ref)

        XCTAssertTrue(signals.versionMentions.isEmpty)
    }

    func test_extractSignals_versionMentionsOrderingDeterministic() async throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let projectDir = base + "/projects/myproject"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        let jsonl = [
            #"{"type":"system","timestamp":"2026-04-01T10:00:00Z","cwd":"/Users/test/project","gitBranch":"main"}"#,
            #"{"type":"user","message":{"role":"user","content":"I need v0.2.5 and v0.3.0 both working"},"timestamp":"2026-04-01T10:00:01Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I will handle v0.2.5 first then v0.3.0."}],"usage":{"input_tokens":100,"output_tokens":30}},"timestamp":"2026-04-01T10:00:02Z"}"#
        ].joined(separator: "\n")
        try jsonl.write(toFile: projectDir + "/vm-deterministic.jsonl", atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(baseDirectory: base)
        let ref = SessionRef(providerID: "claude", sessionID: "vm-deterministic")

        let signalsA = try await provider.extractSignals(for: ref)
        let signalsB = try await provider.extractSignals(for: ref)

        XCTAssertEqual(signalsA.versionMentions, signalsB.versionMentions)
        XCTAssertFalse(signalsA.versionMentions.isEmpty)
    }
}
