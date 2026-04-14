// Tests/EvalHarnessTests/GateCheckTests.swift
import XCTest
@testable import EvalHarnessCore

final class GateCheckTests: XCTestCase {

    // MARK: - Helpers

    private func makeCanonicalArtifact(
        tagLabel: String = "v0.2.8",
        commitSHA: String = "abc123",
        mode: RunArtifact.Mode = .release,
        provider: String = "dashscope",
        model: String = "qwen-plus",
        temperature: Double = 0.0,
        promptBuilderHash: String = "sha256:deadbeef",
        dslSchemaVersion: String = "1",
        gateResult: RunArtifact.GateResult = .pass
    ) -> RunArtifact {
        RunArtifact(
            artifactSchemaVersion: "1",
            tagLabel: tagLabel,
            generatedAt: "2026-04-10T12:00:00Z",
            commitSHA: commitSHA,
            mode: mode,
            provider: provider,
            model: model,
            temperature: temperature,
            dslSchemaVersion: dslSchemaVersion,
            promptBuilderHash: promptBuilderHash,
            promptBuilderHashInputs: RunArtifact.PromptBuilderHashInputs(
                sourceFiles: [],
                algorithm: "sha256"
            ),
            fixtureResults: [],
            summary: RunArtifact.Summary(
                totalFixtures: 0, passedFixtures: 0,
                failedFixtures: 0, totalViolations: 0
            ),
            gateResult: gateResult
        )
    }

    private func writeTempArtifact(_ artifact: RunArtifact, to dir: URL, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(artifact)
        try data.write(to: url)
        return url
    }

    // MARK: - GateCheck.findMatchingArtifact

    func test_findMatchingArtifact_uniqueMatch_returnsArtifact() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-check-unique-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let artifact = makeCanonicalArtifact(tagLabel: "v0.2.8", commitSHA: "abc123")
        try writeTempArtifact(artifact, to: tmpDir, filename: "run.json")

        let (found, _) = try GateCheck.findMatchingArtifact(in: tmpDir, tag: "v0.2.8", candidateSHA: "abc123")
        XCTAssertEqual(found.tagLabel, "v0.2.8")
        XCTAssertEqual(found.commitSHA, "abc123")
    }

    func test_findMatchingArtifact_noMatch_throwsNoMatchingArtifact() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-check-nomatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write an artifact with a different tag
        let artifact = makeCanonicalArtifact(tagLabel: "v0.2.7", commitSHA: "abc123")
        try writeTempArtifact(artifact, to: tmpDir, filename: "run.json")

        XCTAssertThrowsError(
            try GateCheck.findMatchingArtifact(in: tmpDir, tag: "v0.2.8", candidateSHA: "abc123")
        ) { error in
            guard case GateCheckFailure.noMatchingArtifact = error else {
                XCTFail("Expected noMatchingArtifact, got \(error)")
                return
            }
        }
    }

    func test_findMatchingArtifact_emptyDirectory_throwsNoMatchingArtifact() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-check-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try GateCheck.findMatchingArtifact(in: tmpDir, tag: "v0.2.8", candidateSHA: "abc123")
        ) { error in
            guard case GateCheckFailure.noMatchingArtifact = error else {
                XCTFail("Expected noMatchingArtifact, got \(error)")
                return
            }
        }
    }

    func test_findMatchingArtifact_multipleMatches_throwsMultipleMatchingArtifacts() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-check-multi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let artifact = makeCanonicalArtifact(tagLabel: "v0.2.8", commitSHA: "abc123")
        try writeTempArtifact(artifact, to: tmpDir, filename: "run1.json")
        try writeTempArtifact(artifact, to: tmpDir, filename: "run2.json")

        XCTAssertThrowsError(
            try GateCheck.findMatchingArtifact(in: tmpDir, tag: "v0.2.8", candidateSHA: "abc123")
        ) { error in
            guard case GateCheckFailure.multipleMatchingArtifacts(let tag, _, let paths) = error else {
                XCTFail("Expected multipleMatchingArtifacts, got \(error)")
                return
            }
            XCTAssertEqual(tag, "v0.2.8")
            XCTAssertEqual(paths.count, 2)
        }
    }

    func test_findMatchingArtifact_devModeArtifactNotMatched() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-check-devmode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // dev-mode artifact should NOT be matched (GateCheck requires mode=release)
        let artifact = makeCanonicalArtifact(tagLabel: "v0.2.8", commitSHA: "abc123", mode: .dev)
        try writeTempArtifact(artifact, to: tmpDir, filename: "run.json")

        XCTAssertThrowsError(
            try GateCheck.findMatchingArtifact(in: tmpDir, tag: "v0.2.8", candidateSHA: "abc123")
        ) { error in
            guard case GateCheckFailure.noMatchingArtifact = error else {
                XCTFail("Expected noMatchingArtifact, got \(error)")
                return
            }
        }
    }

    // MARK: - GateCheck.verify

    func test_verify_canonicalArtifact_passes() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(promptBuilderHash: currentHash)
        XCTAssertNoThrow(try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash))
    }

    func test_verify_modeIsNotRelease_throws() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(mode: .dev, promptBuilderHash: currentHash)
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash)
        ) { error in
            guard case GateCheckFailure.modeIsNotRelease(let found) = error else {
                XCTFail("Expected modeIsNotRelease, got \(error)")
                return
            }
            XCTAssertEqual(found, "dev")
        }
    }

    func test_verify_providerMismatch_throws() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(provider: "openai", promptBuilderHash: currentHash)
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash)
        ) { error in
            guard case GateCheckFailure.providerMismatch(let expected, let found) = error else {
                XCTFail("Expected providerMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, CanonicalGate.provider)
            XCTAssertEqual(found, "openai")
        }
    }

    func test_verify_modelMismatch_throws() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(model: "gpt-4o", promptBuilderHash: currentHash)
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash)
        ) { error in
            guard case GateCheckFailure.modelMismatch(let expected, let found) = error else {
                XCTFail("Expected modelMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, CanonicalGate.model)
            XCTAssertEqual(found, "gpt-4o")
        }
    }

    func test_verify_temperatureMismatch_throws() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(temperature: 0.7, promptBuilderHash: currentHash)
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash)
        ) { error in
            guard case GateCheckFailure.temperatureMismatch(let expected, let found) = error else {
                XCTFail("Expected temperatureMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, CanonicalGate.temperature)
            XCTAssertEqual(found, 0.7)
        }
    }

    func test_verify_promptBuilderHashMismatch_throws() throws {
        let artifact = makeCanonicalArtifact(promptBuilderHash: "sha256:stale")
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: "sha256:current")
        ) { error in
            guard case GateCheckFailure.promptBuilderHashMismatch(let expected, let found) = error else {
                XCTFail("Expected promptBuilderHashMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, "sha256:current")
            XCTAssertEqual(found, "sha256:stale")
        }
    }

    func test_verify_dslSchemaVersionMismatch_throws() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(promptBuilderHash: currentHash, dslSchemaVersion: "99")
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash)
        ) { error in
            guard case GateCheckFailure.dslSchemaVersionMismatch(let expected, let found) = error else {
                XCTFail("Expected dslSchemaVersionMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, CanonicalGate.dslSchemaVersion)
            XCTAssertEqual(found, "99")
        }
    }

    func test_verify_gateResultNotPass_throws() throws {
        let currentHash = PromptBuilderHasher.currentHash()
        let artifact = makeCanonicalArtifact(promptBuilderHash: currentHash, gateResult: .fail)
        XCTAssertThrowsError(
            try GateCheck.verify(artifact: artifact, currentPromptHash: currentHash)
        ) { error in
            guard case GateCheckFailure.gateResultNotPass(let found) = error else {
                XCTFail("Expected gateResultNotPass, got \(error)")
                return
            }
            XCTAssertEqual(found, "FAIL")
        }
    }
}
