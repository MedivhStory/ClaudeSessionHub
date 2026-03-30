import Foundation

/// A deterministic provider for UI tests. Returns hardcoded fixture sessions
/// so tests are isolated from real ~/.claude data and produce repeatable results.
public final class FixtureProvider: AgentProvider, @unchecked Sendable {
    public let id: ProviderID = "claude"
    public let displayName = "Claude Code"
    public let capabilities: ProviderCapabilities = [.resume, .contextUsage, .errorTracking, .branchInfo]

    public init() {}

    public func discoverSessions() async throws -> [SessionSummary] {
        [
            SessionSummary(
                ref: SessionRef(providerID: "claude", sessionID: "fixture-active-1"),
                title: "重构 event loop", currentTaskSummary: "正在优化并发模型",
                runtimeState: .active, taskPhase: .inProgress,
                cwd: "/Users/test/OACP", branch: "main",
                turnCount: 43, filesTouched: 12, recentErrorCount: 0,
                createdAt: Date().addingTimeInterval(-7 * 24 * 3600),
                lastActiveAt: Date().addingTimeInterval(-300),
                contextUsage: ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 179_897, limit: 1_000_000)
            ),
            SessionSummary(
                ref: SessionRef(providerID: "claude", sessionID: "fixture-stale-1"),
                title: "修复连接池泄漏", currentTaskSummary: "等待上游 PR 合并",
                runtimeState: .stopped, taskPhase: .blocked,
                cwd: "/Users/test/OACP", branch: "fix/conn-pool",
                turnCount: 28, filesTouched: 5, recentErrorCount: 2,
                createdAt: Date().addingTimeInterval(-10 * 24 * 3600),
                lastActiveAt: Date().addingTimeInterval(-3 * 24 * 3600),
                contextUsage: nil
            ),
            SessionSummary(
                ref: SessionRef(providerID: "claude", sessionID: "fixture-done-1"),
                title: "初始化项目结构", currentTaskSummary: "搭建基础骨架",
                runtimeState: .stopped, taskPhase: .done,
                cwd: "/Users/test/openclaw", branch: "main",
                turnCount: 15, filesTouched: 8, recentErrorCount: 0,
                createdAt: Date().addingTimeInterval(-14 * 24 * 3600),
                lastActiveAt: Date().addingTimeInterval(-14 * 24 * 3600),
                contextUsage: nil
            ),
            SessionSummary(
                ref: SessionRef(providerID: "claude", sessionID: "fixture-context-high"),
                title: "大型重构迁移", currentTaskSummary: "Redux → Zustand 80%",
                runtimeState: .stopped, taskPhase: .inProgress,
                cwd: "/Users/test/openclaw", branch: "refactor/zustand",
                turnCount: 127, filesTouched: 34, recentErrorCount: 1,
                createdAt: Date().addingTimeInterval(-5 * 24 * 3600),
                lastActiveAt: Date().addingTimeInterval(-1 * 24 * 3600),
                contextUsage: ContextUsage(inputTokens: 3, cacheCreationTokens: 1000, cacheReadTokens: 818_997, limit: 1_000_000)
            ),
        ]
    }

    public func loadSessionDetail(for ref: SessionRef) async throws -> SessionDetail {
        let sessions = try await discoverSessions()
        guard let s = sessions.first(where: { $0.ref == ref }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return SessionDetail(
            summary: s,
            totalErrorCount: s.recentErrorCount + 1,
            cumulativeTokens: TokenBreakdown(inputTokens: 5000, outputTokens: 2000, cacheReadTokens: 1000, cacheWriteTokens: 500),
            recentFiles: ["/test/a.swift", "/test/b.swift"],
            nextStep: "接下来运行测试确认功能正常",
            modelInfo: ModelInfo(modelName: "claude-opus-4-6", contextLimit: 1_000_000)
        )
    }

    public func makeResumeTarget(for ref: SessionRef) throws -> ResumeTarget {
        ResumeTarget(
            executable: "claude",
            arguments: ["-r", ref.sessionID],
            workingDirectory: nil,
            displayCommand: "claude -r \(ref.sessionID)"
        )
    }

    public func refreshRuntimeState(for refs: [SessionRef]) async -> [SessionRef: SessionRuntimeState] {
        var result: [SessionRef: SessionRuntimeState] = [:]
        for ref in refs {
            result[ref] = ref.sessionID.contains("active") ? .alive(pid: 12345) : .dead
        }
        return result
    }
}
