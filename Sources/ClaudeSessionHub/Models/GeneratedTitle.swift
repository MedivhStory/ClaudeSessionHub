import Foundation

/// Source of a generated title — the v0.2.5+ LLM slot.
public enum TitleSource: String, Sendable, Codable {
    case rule
    case placeholder  // Gate-failed descriptive title, auto-upgrades when gate passes
    // Future: case llm
}

/// A generated title with provenance tracking.
public struct GeneratedTitle: Sendable, Codable {
    public let text: String
    public let source: TitleSource
    public let generatedAt: Date

    public init(text: String, source: TitleSource, generatedAt: Date) {
        self.text = text
        self.source = source
        self.generatedAt = generatedAt
    }
}

/// Tracks title evolution for a session.
public struct TitleHistory: Sendable, Codable {
    public let sessionID: String
    public private(set) var entries: [GeneratedTitle] = []

    public var current: GeneratedTitle? { entries.last }

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public mutating func append(_ title: GeneratedTitle) {
        entries.append(title)
    }
}
