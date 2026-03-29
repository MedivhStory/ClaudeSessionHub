import Foundation

struct SessionRef: Hashable, Sendable {
    let providerID: ProviderID
    let sessionID: String
}

enum RuntimeState: String, Sendable, CaseIterable {
    case active, stopped
}

enum TaskPhase: String, Sendable, CaseIterable {
    case inProgress, blocked, done, unknown
}

struct ContextUsage: Sendable, Equatable {
    let inputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let limit: Int

    var promptContext: Int { inputTokens + cacheCreationTokens + cacheReadTokens }
    var percentage: Double { limit > 0 ? Double(promptContext) / Double(limit) : 0 }
}

struct TokenBreakdown: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

struct SessionSummary: Identifiable, Sendable {
    let ref: SessionRef
    let title: String
    let currentTaskSummary: String?
    let runtimeState: RuntimeState
    let taskPhase: TaskPhase
    let cwd: String?
    let branch: String?
    let turnCount: Int
    let filesTouched: Int
    let recentErrorCount: Int
    let createdAt: Date
    let lastActiveAt: Date
    let contextUsage: ContextUsage?

    var id: SessionRef { ref }
}

struct SessionDetail: Sendable {
    let summary: SessionSummary
    let totalErrorCount: Int
    let cumulativeTokens: TokenBreakdown?
    let recentFiles: [String]
    let nextStep: String?
    let modelInfo: ModelInfo?
}

enum SessionRuntimeState: Sendable {
    case alive(pid: Int32)
    case dead
}
