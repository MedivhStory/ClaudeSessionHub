import Foundation

public struct SessionRef: Hashable, Sendable {
    public let providerID: ProviderID
    public let sessionID: String
    public init(providerID: ProviderID, sessionID: String) {
        self.providerID = providerID
        self.sessionID = sessionID
    }
}

public enum RuntimeState: String, Sendable, CaseIterable {
    case active, stopped
}

public enum TaskPhase: String, Sendable, CaseIterable {
    case inProgress, blocked, done, unknown
}

public struct ContextUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let limit: Int

    public var promptContext: Int { inputTokens + cacheCreationTokens + cacheReadTokens }
    public var percentage: Double { limit > 0 ? Double(promptContext) / Double(limit) : 0 }

    public init(inputTokens: Int, cacheCreationTokens: Int, cacheReadTokens: Int, limit: Int) {
        self.inputTokens = inputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.limit = limit
    }
}

public struct TokenBreakdown: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }

    public init(inputTokens: Int, outputTokens: Int, cacheReadTokens: Int, cacheWriteTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }
}

public struct SessionSummary: Identifiable, Sendable {
    public let ref: SessionRef
    public let title: String
    public let currentTaskSummary: String?
    public let runtimeState: RuntimeState
    public let taskPhase: TaskPhase
    public let cwd: String?
    public let branch: String?
    public let turnCount: Int
    public let filesTouched: Int
    public let recentErrorCount: Int
    public let createdAt: Date
    public let lastActiveAt: Date
    public let contextUsage: ContextUsage?
    public let smartTitle: GeneratedTitle?
    public let lastProgress: String?
    public let entrypoint: String?

    public var id: SessionRef { ref }

    public init(ref: SessionRef, title: String, currentTaskSummary: String?, runtimeState: RuntimeState, taskPhase: TaskPhase, cwd: String?, branch: String?, turnCount: Int, filesTouched: Int, recentErrorCount: Int, createdAt: Date, lastActiveAt: Date, contextUsage: ContextUsage?, smartTitle: GeneratedTitle? = nil, lastProgress: String? = nil, entrypoint: String? = nil) {
        self.ref = ref; self.title = title; self.currentTaskSummary = currentTaskSummary
        self.runtimeState = runtimeState; self.taskPhase = taskPhase; self.cwd = cwd
        self.branch = branch; self.turnCount = turnCount; self.filesTouched = filesTouched
        self.recentErrorCount = recentErrorCount; self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt; self.contextUsage = contextUsage
        self.smartTitle = smartTitle; self.lastProgress = lastProgress; self.entrypoint = entrypoint
    }
}

public struct SessionDetail: Sendable {
    public let summary: SessionSummary
    public let totalErrorCount: Int
    public let cumulativeTokens: TokenBreakdown?
    public let recentFiles: [String]
    public let nextStep: String?
    public let modelInfo: ModelInfo?

    public init(summary: SessionSummary, totalErrorCount: Int, cumulativeTokens: TokenBreakdown?, recentFiles: [String], nextStep: String?, modelInfo: ModelInfo?) {
        self.summary = summary; self.totalErrorCount = totalErrorCount
        self.cumulativeTokens = cumulativeTokens; self.recentFiles = recentFiles
        self.nextStep = nextStep; self.modelInfo = modelInfo
    }
}

public enum SessionRuntimeState: Sendable {
    case alive(pid: Int32)
    case dead
}
