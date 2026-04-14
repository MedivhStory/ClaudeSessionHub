// Tests/EvalHarnessTests/RunArtifactTests.swift
import XCTest
@testable import EvalHarnessCore

final class RunArtifactTests: XCTestCase {

    // MARK: - Helpers

    private func makeMinimalArtifact() -> RunArtifact {
        RunArtifact(
            artifactSchemaVersion: "1",
            tagLabel: "v0.2.8",
            generatedAt: "2026-04-10T12:00:00Z",
            commitSHA: "abc123def456",
            mode: .release,
            provider: "dashscope",
            model: "qwen-plus",
            temperature: 0.0,
            dslSchemaVersion: "1",
            promptBuilderHash: "sha256:deadbeef",
            promptBuilderHashInputs: RunArtifact.PromptBuilderHashInputs(
                sourceFiles: ["Sources/Prompts/TitlePromptBuilder.swift"],
                algorithm: "sha256"
            ),
            fixtureResults: [
                RunArtifact.FixtureResult(
                    id: "fixture-001",
                    passed: true,
                    rawOutput: RunArtifact.FixtureResult.RawOutput(
                        title: "Parser rewrite complete",
                        summary: "Rewrote the parser module.",
                        latencySeconds: 1.23
                    ),
                    violations: []
                )
            ],
            summary: RunArtifact.Summary(
                totalFixtures: 1,
                passedFixtures: 1,
                failedFixtures: 0,
                totalViolations: 0
            ),
            gateResult: .pass
        )
    }

    // MARK: - Tests

    func test_runArtifact_jsonRoundTrip() throws {
        let artifact = makeMinimalArtifact()

        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(RunArtifact.self, from: data)

        XCTAssertEqual(decoded, artifact)
        XCTAssertEqual(decoded.artifactSchemaVersion, "1")
        XCTAssertEqual(decoded.tagLabel, "v0.2.8")
        XCTAssertEqual(decoded.commitSHA, "abc123def456")
        XCTAssertEqual(decoded.gateResult, .pass)
        XCTAssertEqual(decoded.fixtureResults.count, 1)
        XCTAssertTrue(decoded.fixtureResults[0].passed)
    }

    func test_mode_rawValues() throws {
        XCTAssertEqual(RunArtifact.Mode.release.rawValue, "release")
        XCTAssertEqual(RunArtifact.Mode.dev.rawValue, "dev")
    }

    func test_gateResult_rawValues() throws {
        XCTAssertEqual(RunArtifact.GateResult.pass.rawValue, "PASS")
        XCTAssertEqual(RunArtifact.GateResult.fail.rawValue, "FAIL")
    }

    func test_tagLabel_present_inArtifact() throws {
        let artifact = makeMinimalArtifact()
        let data = try JSONEncoder().encode(artifact)

        // Verify tagLabel is present in JSON
        let json = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        let decoded = try JSONDecoder().decode(RunArtifact.self, from: data)
        XCTAssertEqual(decoded.tagLabel, "v0.2.8")

        // Also verify the raw JSON contains the key
        let jsonString = String(data: data, encoding: .utf8)!
        XCTAssertTrue(jsonString.contains("tagLabel"))
        XCTAssertTrue(jsonString.contains("v0.2.8"))
    }

    func test_promptBuilderHash_present() throws {
        let artifact = makeMinimalArtifact()
        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(RunArtifact.self, from: data)

        XCTAssertEqual(decoded.promptBuilderHash, "sha256:deadbeef")
        XCTAssertEqual(decoded.promptBuilderHashInputs.algorithm, "sha256")
        XCTAssertEqual(decoded.promptBuilderHashInputs.sourceFiles.count, 1)
        XCTAssertEqual(
            decoded.promptBuilderHashInputs.sourceFiles[0],
            "Sources/Prompts/TitlePromptBuilder.swift"
        )

        let jsonString = String(data: data, encoding: .utf8)!
        XCTAssertTrue(jsonString.contains("promptBuilderHash"))
        XCTAssertTrue(jsonString.contains("promptBuilderHashInputs"))
    }

    func test_violation_roundTrip() throws {
        let violation = RunArtifact.ViolationPayload(
            fixtureID: "fixture-002",
            field: "title",
            constraint: "minLength",
            expected: ">=10",
            actual: "Hi",
            message: "title length 2 < minLength 10"
        )
        let artifact = RunArtifact(
            artifactSchemaVersion: "1",
            tagLabel: "v0.2.8",
            generatedAt: "2026-04-10T12:00:00Z",
            commitSHA: "abc123",
            mode: .dev,
            provider: "dashscope",
            model: "qwen-plus",
            temperature: 0.0,
            dslSchemaVersion: "1",
            promptBuilderHash: "sha256:abcdef",
            promptBuilderHashInputs: RunArtifact.PromptBuilderHashInputs(
                sourceFiles: [],
                algorithm: "sha256"
            ),
            fixtureResults: [
                RunArtifact.FixtureResult(
                    id: "fixture-002",
                    passed: false,
                    rawOutput: RunArtifact.FixtureResult.RawOutput(title: "Hi"),
                    violations: [violation]
                )
            ],
            summary: RunArtifact.Summary(
                totalFixtures: 1,
                passedFixtures: 0,
                failedFixtures: 1,
                totalViolations: 1
            ),
            gateResult: .fail
        )

        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(RunArtifact.self, from: data)

        XCTAssertEqual(decoded.gateResult, .fail)
        XCTAssertEqual(decoded.fixtureResults[0].violations[0].message, "title length 2 < minLength 10")
        XCTAssertEqual(decoded.mode, .dev)
    }
}

// MARK: - Minimal AnyCodable helper for JSON key presence check

private struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {
        // Just try to decode - we only care that we can
        if let _ = try? decoder.singleValueContainer().decode(String.self) { return }
        if let _ = try? decoder.singleValueContainer().decode(Int.self) { return }
        if let _ = try? decoder.singleValueContainer().decode(Bool.self) { return }
        if let _ = try? decoder.singleValueContainer().decode(Double.self) { return }
    }
    func encode(to encoder: Encoder) throws {}
}
