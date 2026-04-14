// Sources/EvalHarnessCore/RunArtifact.swift
import Foundation

/// Top-level artifact produced by a harness evaluation run.
/// Written to `gate-runs/<tag>/<timestamp>-<sha>.json`.
public struct RunArtifact: Codable, Sendable, Equatable {

    // MARK: - Metadata

    /// Format version for the artifact schema itself.
    public let artifactSchemaVersion: String
    /// The release tag this run was generated for (e.g. "v0.2.8").
    public let tagLabel: String
    /// Wall-clock timestamp of the run (ISO-8601).
    public let generatedAt: String
    /// Git commit SHA of the code being evaluated.
    public let commitSHA: String
    /// Run mode: release (CI) or dev (local).
    public let mode: Mode
    /// LLM provider used (e.g. "dashscope").
    public let provider: String
    /// LLM model used (e.g. "qwen-plus").
    public let model: String
    /// Temperature used for inference.
    public let temperature: Double
    /// DSL schema version of the fixtures consumed.
    public let dslSchemaVersion: String
    /// SHA-256 hash of the prompt builder source used.
    public let promptBuilderHash: String
    /// Inputs used to compute `promptBuilderHash`.
    public let promptBuilderHashInputs: PromptBuilderHashInputs
    /// Per-fixture results.
    public let fixtureResults: [FixtureResult]
    /// Aggregate summary.
    public let summary: Summary
    /// Overall gate decision.
    public let gateResult: GateResult

    public init(
        artifactSchemaVersion: String,
        tagLabel: String,
        generatedAt: String,
        commitSHA: String,
        mode: Mode,
        provider: String,
        model: String,
        temperature: Double,
        dslSchemaVersion: String,
        promptBuilderHash: String,
        promptBuilderHashInputs: PromptBuilderHashInputs,
        fixtureResults: [FixtureResult],
        summary: Summary,
        gateResult: GateResult
    ) {
        self.artifactSchemaVersion = artifactSchemaVersion
        self.tagLabel = tagLabel
        self.generatedAt = generatedAt
        self.commitSHA = commitSHA
        self.mode = mode
        self.provider = provider
        self.model = model
        self.temperature = temperature
        self.dslSchemaVersion = dslSchemaVersion
        self.promptBuilderHash = promptBuilderHash
        self.promptBuilderHashInputs = promptBuilderHashInputs
        self.fixtureResults = fixtureResults
        self.summary = summary
        self.gateResult = gateResult
    }

    // MARK: - Mode

    public enum Mode: String, Codable, Sendable, Equatable {
        case release = "release"
        case dev = "dev"
    }

    // MARK: - GateResult

    public enum GateResult: String, Codable, Sendable, Equatable {
        case pass = "PASS"
        case fail = "FAIL"
    }

    // MARK: - PromptBuilderHashInputs

    /// The set of source files whose content was hashed to produce `promptBuilderHash`.
    public struct PromptBuilderHashInputs: Codable, Sendable, Equatable {
        /// Relative paths of Swift source files included in the hash.
        public let sourceFiles: [String]
        /// Algorithm used (e.g. "sha256").
        public let algorithm: String

        public init(sourceFiles: [String], algorithm: String) {
            self.sourceFiles = sourceFiles
            self.algorithm = algorithm
        }
    }

    // MARK: - FixtureResult

    /// Result for a single fixture pair evaluation.
    public struct FixtureResult: Codable, Sendable, Equatable {
        public let id: String
        public let passed: Bool
        public let rawOutput: RawOutput
        public let violations: [ViolationPayload]
        public let snapshot: SnapshotPayload?

        public init(
            id: String,
            passed: Bool,
            rawOutput: RawOutput,
            violations: [ViolationPayload],
            snapshot: SnapshotPayload? = nil
        ) {
            self.id = id
            self.passed = passed
            self.rawOutput = rawOutput
            self.violations = violations
            self.snapshot = snapshot
        }

        /// The raw LLM response for this fixture.
        public struct RawOutput: Codable, Sendable, Equatable {
            public let title: String
            public let summary: String?
            public let latencySeconds: Double?
            public let tokenUsage: TokenUsage?

            public init(
                title: String,
                summary: String? = nil,
                latencySeconds: Double? = nil,
                tokenUsage: TokenUsage? = nil
            ) {
                self.title = title
                self.summary = summary
                self.latencySeconds = latencySeconds
                self.tokenUsage = tokenUsage
            }
        }

        public struct TokenUsage: Codable, Sendable, Equatable {
            public let promptTokens: Int
            public let completionTokens: Int
            public let totalTokens: Int

            public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
                self.promptTokens = promptTokens
                self.completionTokens = completionTokens
                self.totalTokens = totalTokens
            }
        }
    }

    // MARK: - ViolationPayload

    /// Describes a single constraint violation on an output field.
    public struct ViolationPayload: Codable, Sendable, Equatable {
        public let fixtureID: String
        public let field: String
        public let constraint: String
        public let expected: String
        public let actual: String
        public let message: String

        public init(
            fixtureID: String,
            field: String,
            constraint: String,
            expected: String,
            actual: String,
            message: String
        ) {
            self.fixtureID = fixtureID
            self.field = field
            self.constraint = constraint
            self.expected = expected
            self.actual = actual
            self.message = message
        }
    }

    // MARK: - SnapshotPayload

    /// Optional captured snapshot data for real-snapshot fixtures.
    public struct SnapshotPayload: Codable, Sendable, Equatable {
        public let capturedAt: String?
        public let sourceSessionID: String?

        public init(capturedAt: String? = nil, sourceSessionID: String? = nil) {
            self.capturedAt = capturedAt
            self.sourceSessionID = sourceSessionID
        }
    }

    // MARK: - Summary

    /// Aggregate statistics for the run.
    public struct Summary: Codable, Sendable, Equatable {
        public let totalFixtures: Int
        public let passedFixtures: Int
        public let failedFixtures: Int
        public let totalViolations: Int

        public init(
            totalFixtures: Int,
            passedFixtures: Int,
            failedFixtures: Int,
            totalViolations: Int
        ) {
            self.totalFixtures = totalFixtures
            self.passedFixtures = passedFixtures
            self.failedFixtures = failedFixtures
            self.totalViolations = totalViolations
        }
    }
}
