import Foundation

/// Complete AI understanding result for one session.
/// Produced by LLMEnhancer, persisted by UnderstandingStore.
public struct LLMUnderstandingSnapshot: Codable, Sendable, Equatable {
    public let sessionID: String
    public let title: String
    public let progress: String?
    public let summary: String?
    public let modelName: String
    public let generatedAt: Date
    /// The session's lastActiveAt when this snapshot was generated.
    /// Used for stale detection: if session.lastActiveAt > basedOnLastActiveAt, snapshot is stale.
    public let basedOnLastActiveAt: Date

    public init(sessionID: String, title: String, progress: String?,
                summary: String?, modelName: String, generatedAt: Date,
                basedOnLastActiveAt: Date) {
        self.sessionID = sessionID
        self.title = title
        self.progress = progress
        self.summary = summary
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.basedOnLastActiveAt = basedOnLastActiveAt
    }
}
