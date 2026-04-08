import Foundation

/// Structured signals extracted from all data sources for a single session.
/// This is the input to title/summary generation — never consumed by UI directly.
public struct SessionSignals: Sendable {
    public let sessionID: String

    // From JSONL user turns
    public var firstUserIntent: String?
    public var lastUserIntent: String?
    public var sampledUserIntents: [String] = []

    // From JSONL assistant turns
    public var lastAssistantProgress: String?

    // From history.jsonl
    public var historyDisplayTexts: [String] = []

    // From tasks/
    public var taskSubject: String?
    public var taskDescription: String?
    public var taskStatus: String?

    // From JSONL metadata
    public var entrypoint: String?
    public var branch: String?
    public var slug: String?
    public var toolsUsed: Set<String> = []
    public var filesModified: Set<String> = []
    public var isSidechain: Bool = false
    public var turnCount: Int = 0

    // For command-only sessions (gate-failed placeholder title generation)
    public var slashCommands: [String] = []       // e.g. ["/resume", "/login"]
    public var commandErrors: [String] = []       // e.g. ["No conversations found to resume"]
    public var hasAssistantReply: Bool = false

    // Session scale indicators (for LLM prompt context)
    public var totalEntryCount: Int = 0
    public var historyCount: Int = 0

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

/// Lightweight relationship between sessions in the same project.
public struct SessionRelation: Sendable {
    public enum RelationType: String, Sendable {
        case sameBranch
        case timeOverlap
        case continuation
    }

    public let otherSessionID: String
    public let type: RelationType

    public init(otherSessionID: String, type: RelationType) {
        self.otherSessionID = otherSessionID
        self.type = type
    }
}
