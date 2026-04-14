// Tests/EvalHarnessTests/LiveRunConfigTests.swift
import XCTest
@testable import EvalHarnessCore

final class LiveRunConfigTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: "/tmp/test-repo")

    // MARK: - Release mode

    func test_releaseMode_usesCanonicalProvider() throws {
        let config = try LiveRunConfig.resolve(
            mode: .release, tag: "v1",
            envProvider: "openai", envModel: "gpt-4",
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.provider, "dashscope")
        XCTAssertEqual(config.model, "qwen-plus")
    }

    func test_releaseMode_requiresTag() {
        XCTAssertThrowsError(
            try LiveRunConfig.resolve(
                mode: .release, tag: nil,
                envProvider: nil, envModel: nil,
                repoRoot: repoRoot
            )
        )
    }

    func test_releaseMode_emptyTagThrows() {
        XCTAssertThrowsError(
            try LiveRunConfig.resolve(
                mode: .release, tag: "",
                envProvider: nil, envModel: nil,
                repoRoot: repoRoot
            )
        )
    }

    func test_releaseMode_usesCanonicalTemperature() throws {
        let config = try LiveRunConfig.resolve(
            mode: .release, tag: "v1",
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.temperature, CanonicalGate.temperature)
    }

    func test_releaseMode_outputDirIsGateRuns() throws {
        let config = try LiveRunConfig.resolve(
            mode: .release, tag: "v1",
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertTrue(config.outputDir.path.contains("docs/eval/gate-runs"))
    }

    func test_releaseMode_tagLabelSet() throws {
        let config = try LiveRunConfig.resolve(
            mode: .release, tag: "v0.2.8",
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.tagLabel, "v0.2.8")
    }

    // MARK: - Dev mode

    func test_devMode_honorsEnvProvider() throws {
        let config = try LiveRunConfig.resolve(
            mode: .dev, tag: nil,
            envProvider: "openai", envModel: "gpt-4",
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.provider, "openai")
        XCTAssertEqual(config.model, "gpt-4")
    }

    func test_devMode_tagDefaultsToDev() throws {
        let config = try LiveRunConfig.resolve(
            mode: .dev, tag: nil,
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.tagLabel, "dev")
    }

    func test_devMode_tagOverride() throws {
        let config = try LiveRunConfig.resolve(
            mode: .dev, tag: "my-branch",
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.tagLabel, "my-branch")
    }

    func test_devMode_outputDirIsDevArtifacts() throws {
        let config = try LiveRunConfig.resolve(
            mode: .dev, tag: nil,
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertTrue(config.outputDir.path.contains("dist/eval-artifacts/dev"))
    }

    func test_devMode_fallsBackToCanonicalProvider_whenEnvNil() throws {
        let config = try LiveRunConfig.resolve(
            mode: .dev, tag: nil,
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.provider, CanonicalGate.provider)
        XCTAssertEqual(config.model, CanonicalGate.model)
    }

    func test_devMode_modeRawValueIsDev() throws {
        let config = try LiveRunConfig.resolve(
            mode: .dev, tag: nil,
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.mode.rawValue, "dev")
    }

    func test_releaseMode_modeRawValueIsRelease() throws {
        let config = try LiveRunConfig.resolve(
            mode: .release, tag: "v1",
            envProvider: nil, envModel: nil,
            repoRoot: repoRoot
        )
        XCTAssertEqual(config.mode.rawValue, "release")
    }
}
