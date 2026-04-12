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
    public let title: FieldConstraints
    public let summary: FieldConstraints?

    public init(
        schemaVersion: String,
        id: String,
        title: FieldConstraints,
        summary: FieldConstraints? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.summary = summary
    }
}

// MARK: - FieldConstraints

/// Constraint operators applied to a single output field (e.g. title, summary).
public struct FieldConstraints: Codable, Sendable, Equatable {
    /// Minimum string length (inclusive).
    public var minLength: Int?
    /// Maximum string length (inclusive).
    public var maxLength: Int?
    /// Regex pattern the field must match.
    public var matches: String?
    /// Regex pattern the field must NOT match.
    public var notMatches: String?
    /// Substring that must appear in the field.
    public var contains: String?
    /// Substring that must NOT appear in the field.
    public var notContains: String?
    /// Exact string the field must equal.
    public var equals: String?
    /// Exact string the field must NOT equal.
    public var notEquals: String?
    /// Human-readable justification for a verbatim constraint (required when the
    /// constraint value verbatim-matches content in the input).
    public var verbatimMatchJustification: String?

    public init(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        matches: String? = nil,
        notMatches: String? = nil,
        contains: String? = nil,
        notContains: String? = nil,
        equals: String? = nil,
        notEquals: String? = nil,
        verbatimMatchJustification: String? = nil
    ) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.matches = matches
        self.notMatches = notMatches
        self.contains = contains
        self.notContains = notContains
        self.equals = equals
        self.notEquals = notEquals
        self.verbatimMatchJustification = verbatimMatchJustification
    }
}

// MARK: - CountConstraint

/// Constraint on the count/cardinality of a repeated field.
public struct CountConstraint: Codable, Sendable, Equatable {
    public var min: Int?
    public var max: Int?
    public var exact: Int?

    public init(min: Int? = nil, max: Int? = nil, exact: Int? = nil) {
        self.min = min
        self.max = max
        self.exact = exact
    }
}
