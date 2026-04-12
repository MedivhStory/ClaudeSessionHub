// Sources/EvalHarnessCore/FixtureSchema.swift
import Foundation
import ClaudeSessionHubLib

// MARK: - FixtureInputFile

/// Codable representation of a `*.input.json` fixture file.
public struct FixtureInputFile: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let id: String
    public let kind: Kind
    public let meta: Meta?
    public let signals: SignalsPayload

    public init(
        schemaVersion: String,
        id: String,
        kind: Kind,
        meta: Meta?,
        signals: SignalsPayload
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.meta = meta
        self.signals = signals
    }

    // MARK: Kind

    public enum Kind: String, Codable, Sendable, Equatable {
        case synthetic = "synthetic"
        case realSnapshot = "real-snapshot"
    }

    // MARK: Meta

    /// Optional metadata for real-snapshot fixtures.
    public struct Meta: Codable, Sendable, Equatable {
        public let sessionID: String?
        public let capturedAt: String?

        public init(sessionID: String? = nil, capturedAt: String? = nil) {
            self.sessionID = sessionID
            self.capturedAt = capturedAt
        }
    }

    // MARK: SignalsPayload

    /// Mirrors `SessionSignals` fields as a Codable fixture payload.
    /// This is a distinct Codable type (not a direct alias of `SessionSignals`).
    public struct SignalsPayload: Codable, Sendable, Equatable {
        public var sessionID: String
        public var firstUserIntent: String?
        public var lastUserIntent: String?
        public var sampledUserIntents: [String]
        public var lastAssistantProgress: String?
        public var historyDisplayTexts: [String]
        public var versionMentions: [VersionMention]
        public var taskSubject: String?
        public var taskDescription: String?
        public var taskStatus: String?
        public var entrypoint: String?
        public var branch: String?
        public var slug: String?
        public var toolsUsed: [String]
        public var filesModified: [String]
        public var isSidechain: Bool
        public var turnCount: Int
        public var slashCommands: [String]
        public var commandErrors: [String]
        public var hasAssistantReply: Bool
        public var totalEntryCount: Int
        public var historyCount: Int

        public init(
            sessionID: String,
            firstUserIntent: String? = nil,
            lastUserIntent: String? = nil,
            sampledUserIntents: [String] = [],
            lastAssistantProgress: String? = nil,
            historyDisplayTexts: [String] = [],
            versionMentions: [VersionMention] = [],
            taskSubject: String? = nil,
            taskDescription: String? = nil,
            taskStatus: String? = nil,
            entrypoint: String? = nil,
            branch: String? = nil,
            slug: String? = nil,
            toolsUsed: [String] = [],
            filesModified: [String] = [],
            isSidechain: Bool = false,
            turnCount: Int = 0,
            slashCommands: [String] = [],
            commandErrors: [String] = [],
            hasAssistantReply: Bool = false,
            totalEntryCount: Int = 0,
            historyCount: Int = 0
        ) {
            self.sessionID = sessionID
            self.firstUserIntent = firstUserIntent
            self.lastUserIntent = lastUserIntent
            self.sampledUserIntents = sampledUserIntents
            self.lastAssistantProgress = lastAssistantProgress
            self.historyDisplayTexts = historyDisplayTexts
            self.versionMentions = versionMentions
            self.taskSubject = taskSubject
            self.taskDescription = taskDescription
            self.taskStatus = taskStatus
            self.entrypoint = entrypoint
            self.branch = branch
            self.slug = slug
            self.toolsUsed = toolsUsed
            self.filesModified = filesModified
            self.isSidechain = isSidechain
            self.turnCount = turnCount
            self.slashCommands = slashCommands
            self.commandErrors = commandErrors
            self.hasAssistantReply = hasAssistantReply
            self.totalEntryCount = totalEntryCount
            self.historyCount = historyCount
        }
    }
}

// MARK: - ExpectedConstraintsFile

/// Codable representation of a `*.expected.json` fixture file.
public struct ExpectedConstraintsFile: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let id: String
    public let title: FieldConstraints?
    public let progress: FieldConstraints?
    public let summary: FieldConstraints?
    public let verbatimMatchJustification: String?

    public init(
        schemaVersion: String = "1",
        id: String,
        title: FieldConstraints? = nil,
        progress: FieldConstraints? = nil,
        summary: FieldConstraints? = nil,
        verbatimMatchJustification: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.progress = progress
        self.summary = summary
        self.verbatimMatchJustification = verbatimMatchJustification
    }
}

// MARK: - FieldConstraints

/// Constraint operators applied to a single output field (e.g. title, summary).
/// Implements the 9-operator constraint DSL (spec §2.3 / Appendix A.2).
public struct FieldConstraints: Codable, Sendable, Equatable {
    /// Output must contain at least one of the listed substrings.
    public let mustContainAny: [String]?
    /// Output must contain every listed substring.
    public let mustContainAll: [String]?
    /// Output must NOT contain any of the listed substrings.
    public let mustNotContain: [String]?
    /// Output (whole string) must NOT equal any listed string.
    public let mustNotEqual: [String]?
    /// If true, output (trimmed) must have length > 0.
    public let mustNotBeEmpty: Bool?
    /// Minimum string length (inclusive).
    public let minLength: Int?
    /// Maximum string length (inclusive).
    public let maxLength: Int?
    /// Regex pattern the field must match (at least one match found).
    public let mustMatchRegex: String?
    /// Number of non-overlapping regex matches must be <= n.
    public let maxRegexMatchCount: CountConstraint?

    public init(
        mustContainAny: [String]? = nil,
        mustContainAll: [String]? = nil,
        mustNotContain: [String]? = nil,
        mustNotEqual: [String]? = nil,
        mustNotBeEmpty: Bool? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        mustMatchRegex: String? = nil,
        maxRegexMatchCount: CountConstraint? = nil
    ) {
        self.mustContainAny = mustContainAny
        self.mustContainAll = mustContainAll
        self.mustNotContain = mustNotContain
        self.mustNotEqual = mustNotEqual
        self.mustNotBeEmpty = mustNotBeEmpty
        self.minLength = minLength
        self.maxLength = maxLength
        self.mustMatchRegex = mustMatchRegex
        self.maxRegexMatchCount = maxRegexMatchCount
    }
}

// MARK: - CountConstraint

/// Constraint on the maximum number of regex matches for a field.
public struct CountConstraint: Codable, Sendable, Equatable {
    /// The regex pattern to count matches of.
    public let pattern: String
    /// The maximum allowed number of non-overlapping matches.
    public let n: Int

    public init(pattern: String, n: Int) {
        self.pattern = pattern
        self.n = n
    }
}
