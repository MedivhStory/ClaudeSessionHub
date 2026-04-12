// Sources/EvalHarnessCLI/main.swift
import Foundation
import EvalHarnessCore
import ClaudeSessionHubLib

// MARK: - Entry point

let args = Array(CommandLine.arguments.dropFirst())

guard let command = args.first else {
    printUsage()
    exit(1)
}

switch command {
case "validate-fixtures":
    runValidateFixtures(args: Array(args.dropFirst()))
case "live":
    runLiveSync(args: Array(args.dropFirst()))
case "check-artifact":
    runCheckArtifact(args: Array(args.dropFirst()))
case "--help", "-h", "help":
    printUsage()
    exit(0)
default:
    FileHandle.standardError.write("Unknown command: \(command)\n".data(using: .utf8)!)
    printUsage()
    exit(1)
}

// MARK: - Usage

func printUsage() {
    let usage = """
    Usage: eval-harness <command> [options]

    Commands:
      validate-fixtures  --fixtures <dir>
      live               --fixtures <dir> [--release|--dev] [--tag <v>]
      check-artifact     --tag <v> [--artifact <path>]

    Run 'eval-harness <command> --help' for details.
    """
    print(usage)
}

// MARK: - Argument parsing

func parseArgs(_ args: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--") {
            let key = String(args[i].dropFirst(2))
            if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                result[key] = args[i + 1]
                i += 2
            } else {
                result[key] = ""  // flag without value
                i += 1
            }
        } else {
            i += 1
        }
    }
    return result
}

// MARK: - validate-fixtures

func runValidateFixtures(args: [String]) {
    let parsed = parseArgs(args)

    if parsed.keys.contains("help") {
        print("Usage: eval-harness validate-fixtures --fixtures <dir>")
        exit(0)
    }

    guard let fixturesDir = parsed["fixtures"] else {
        FileHandle.standardError.write("--fixtures <dir> is required\n".data(using: .utf8)!)
        exit(1)
    }

    let dirURL = URL(fileURLWithPath: fixturesDir)
    let (pairs, errors) = FixtureLoader.loadAndValidate(directory: dirURL)

    if errors.isEmpty {
        print("✓ \(pairs.count) fixtures validated; no errors")
        exit(0)
    } else {
        FileHandle.standardError.write("✗ \(errors.count) validation errors:\n".data(using: .utf8)!)
        for (i, error) in errors.enumerated() {
            FileHandle.standardError.write("  \(i + 1). \(error.description)\n".data(using: .utf8)!)
        }
        exit(1)
    }
}

// MARK: - live (sync wrapper)

func runLiveSync(args: [String]) {
    let sema = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    Task {
        exitCode = await runLive(args: args)
        sema.signal()
    }

    sema.wait()
    exit(exitCode)
}

// MARK: - live (async implementation)

func runLive(args: [String]) async -> Int32 {
    let parsed = parseArgs(args)

    if parsed.keys.contains("help") {
        print("Usage: eval-harness live --fixtures <dir> [--release|--dev] [--tag <v>]")
        return 0
    }

    // Determine mode
    let mode: LiveRunConfig.Mode
    if parsed.keys.contains("release") {
        mode = .release
    } else {
        mode = .dev
    }

    let tag = parsed["tag"]
    let fixturesDir = parsed["fixtures"] ?? "Tests/Fixtures/eval"

    // Find repo root (directory containing Package.swift)
    let repoRoot = findRepoRoot()

    // Resolve config
    let config: LiveRunConfig
    do {
        config = try LiveRunConfig.resolve(
            mode: mode,
            tag: tag,
            envProvider: ProcessInfo.processInfo.environment["EVAL_PROVIDER"],
            envModel: ProcessInfo.processInfo.environment["EVAL_MODEL"],
            repoRoot: repoRoot
        )
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        return 1
    }

    // Load fixtures
    let dirURL = URL(fileURLWithPath: fixturesDir)
    let (pairs, loadErrors) = FixtureLoader.loadAndValidate(directory: dirURL)
    if !loadErrors.isEmpty {
        FileHandle.standardError.write("✗ Fixture validation errors:\n".data(using: .utf8)!)
        for err in loadErrors {
            FileHandle.standardError.write("  - \(err.description)\n".data(using: .utf8)!)
        }
        return 1
    }
    if pairs.isEmpty {
        FileHandle.standardError.write("✗ No fixtures found in \(fixturesDir)\n".data(using: .utf8)!)
        return 1
    }

    print("eval-harness live [\(config.mode.rawValue)] — \(pairs.count) fixtures, provider=\(config.provider), model=\(config.model)")

    // Build LLMConfig from LiveRunConfig
    let llmConfig = buildLLMConfig(from: config)
    guard llmConfig.isConfigured else {
        FileHandle.standardError.write("✗ LLM not configured. Set EVAL_API_KEY or ensure ~/.claude-hub/.apiKey.secret exists.\n".data(using: .utf8)!)
        return 1
    }

    let enhancer = LLMEnhancer(config: llmConfig)
    let commitSHA = getGitHeadSHA()
    let promptHash = PromptBuilderHasher.currentHash()
    let hashInputs = buildPromptHashInputs()
    let runStarted = ISO8601DateFormatter().string(from: Date())

    var fixtureResults: [RunArtifact.FixtureResult] = []
    var totalViolations = 0
    var passedCount = 0

    for pair in pairs {
        print("  → \(pair.id) …", terminator: "")
        fflush(stdout)

        let signals = signalsFromPayload(pair.input.signals)
        let startTime = Date()
        let snapshot = await enhancer.enhance(
            signals: signals,
            rawTurns: [],
            basedOnLastActiveAt: startTime
        )
        let latency = Date().timeIntervalSince(startTime)

        guard let snapshot = snapshot else {
            FileHandle.standardError.write("\n✗ LLM call returned nil for fixture \(pair.id)\n".data(using: .utf8)!)
            let result = RunArtifact.FixtureResult(
                id: pair.id,
                passed: false,
                rawOutput: RunArtifact.FixtureResult.RawOutput(
                    title: "",
                    summary: nil,
                    latencySeconds: latency,
                    tokenUsage: nil
                ),
                violations: [RunArtifact.ViolationPayload(
                    fixtureID: pair.id,
                    field: "title",
                    constraint: "llm-call",
                    expected: "non-nil LLM response",
                    actual: "nil",
                    message: "LLM call returned nil — check API key and provider configuration"
                )]
            )
            fixtureResults.append(result)
            totalViolations += 1
            continue
        }

        let verificationResult = Verifier.verify(
            fixtureID: pair.id,
            snapshot: snapshot,
            expected: pair.expected
        )

        let violations = verificationResult.violations.map { v in
            RunArtifact.ViolationPayload(
                fixtureID: pair.id,
                field: v.field.rawValue,
                constraint: v.constraint.rawValue,
                expected: v.expected,
                actual: v.actual,
                message: "\(v.field.rawValue).\(v.constraint.rawValue): expected \(v.expected), got \(v.actual)"
            )
        }

        let snapshotPayload: RunArtifact.SnapshotPayload?
        if pair.input.kind == .realSnapshot {
            snapshotPayload = RunArtifact.SnapshotPayload(
                capturedAt: pair.input.meta?.capturedAt,
                sourceSessionID: pair.input.meta?.sessionID
            )
        } else {
            snapshotPayload = nil
        }

        let result = RunArtifact.FixtureResult(
            id: pair.id,
            passed: verificationResult.passed,
            rawOutput: RunArtifact.FixtureResult.RawOutput(
                title: snapshot.title,
                summary: snapshot.summary,
                latencySeconds: latency,
                tokenUsage: nil
            ),
            violations: violations,
            snapshot: snapshotPayload
        )
        fixtureResults.append(result)
        totalViolations += violations.count
        if verificationResult.passed { passedCount += 1 }

        let status = verificationResult.passed ? "✓" : "✗"
        print(" \(status) \"\(snapshot.title)\"")
    }

    let failedCount = pairs.count - passedCount
    let gateResult: RunArtifact.GateResult = failedCount == 0 ? .pass : .fail

    let summary = RunArtifact.Summary(
        totalFixtures: pairs.count,
        passedFixtures: passedCount,
        failedFixtures: failedCount,
        totalViolations: totalViolations
    )

    let artifactMode: RunArtifact.Mode = config.mode == .release ? .release : .dev

    let artifact = RunArtifact(
        artifactSchemaVersion: "1",
        tagLabel: config.tagLabel,
        generatedAt: runStarted,
        commitSHA: commitSHA,
        mode: artifactMode,
        provider: config.provider,
        model: config.model,
        temperature: config.temperature,
        dslSchemaVersion: CanonicalGate.dslSchemaVersion,
        promptBuilderHash: promptHash,
        promptBuilderHashInputs: hashInputs,
        fixtureResults: fixtureResults,
        summary: summary,
        gateResult: gateResult
    )

    // Write artifact
    let fm = FileManager.default
    try? fm.createDirectory(at: config.outputDir, withIntermediateDirectories: true)
    let shortSHA = String(commitSHA.prefix(8))
    let dateStr = String(runStarted.prefix(10))  // "YYYY-MM-DD"
    let filename = "\(dateStr)-\(config.tagLabel)-\(shortSHA).json"
    let outputURL = config.outputDir.appendingPathComponent(filename)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(artifact) {
        try? data.write(to: outputURL)
        print("✓ Artifact written to \(outputURL.path)")
    } else {
        FileHandle.standardError.write("✗ Failed to encode artifact\n".data(using: .utf8)!)
    }

    print("\nSummary: \(passedCount)/\(pairs.count) fixtures passed — gateResult=\(gateResult.rawValue)")

    return gateResult == .pass ? 0 : 1
}

// MARK: - check-artifact

func runCheckArtifact(args: [String]) {
    let parsed = parseArgs(args)

    if parsed.keys.contains("help") {
        print("Usage: eval-harness check-artifact --tag <v> [--artifact <path>]")
        exit(0)
    }

    guard let tag = parsed["tag"] else {
        FileHandle.standardError.write("--tag <v> is required\n".data(using: .utf8)!)
        exit(1)
    }

    let repoRoot = findRepoRoot()
    let gateRunsDir = repoRoot.appendingPathComponent("docs/eval/gate-runs", isDirectory: true)

    // Get candidate SHA (HEAD^)
    let candidateSHA = getGitParentSHA()
    let currentPromptHash = PromptBuilderHasher.currentHash()

    do {
        let artifact: RunArtifact

        if let explicitPath = parsed["artifact"] {
            // Explicit path: load directly, skip directory scan
            let data = try Data(contentsOf: URL(fileURLWithPath: explicitPath))
            artifact = try JSONDecoder().decode(RunArtifact.self, from: data)
            // Still validate triple-filter
            if artifact.tagLabel != tag {
                throw GateCheckFailure.noMatchingArtifact(tag: tag, candidateSHA: candidateSHA)
            }
            if artifact.mode != .release {
                throw GateCheckFailure.modeIsNotRelease(found: artifact.mode.rawValue)
            }
            if artifact.commitSHA != candidateSHA {
                throw GateCheckFailure.commitShaMismatch(expected: candidateSHA, found: artifact.commitSHA)
            }
        } else {
            // Auto-match: strict unique
            let (found, _) = try GateCheck.findMatchingArtifact(
                in: gateRunsDir,
                tag: tag,
                candidateSHA: candidateSHA
            )
            artifact = found
        }

        // 8-way binding check
        try GateCheck.verify(artifact: artifact, currentPromptHash: currentPromptHash)

        print("✓ Gate check passed for tag '\(tag)'")
        print("  commitSHA: \(artifact.commitSHA)")
        print("  promptBuilderHash: \(artifact.promptBuilderHash)")
        print("  provider: \(artifact.provider) / \(artifact.model)")
        print("  gateResult: \(artifact.gateResult.rawValue)")
        exit(0)

    } catch let error as GateCheckFailure {
        FileHandle.standardError.write("✗ Gate check failed: \(error.description)\n".data(using: .utf8)!)
        exit(1)
    } catch {
        FileHandle.standardError.write("✗ Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - Helpers

func findRepoRoot() -> URL {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
        let parent = dir.deletingLastPathComponent()
        if parent == dir { break }
        dir = parent
    }
    return dir
}

func getGitHeadSHA() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "HEAD"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
}

func getGitParentSHA() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "HEAD^"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()  // suppress stderr
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
}

/// Build LLMConfig from LiveRunConfig, loading API key from EVAL_API_KEY env or FileSecretStore.
func buildLLMConfig(from liveConfig: LiveRunConfig) -> LLMConfig {
    let providerEnum = LLMProvider(rawValue: liveConfig.provider) ?? .custom
    var llmConfig = LLMConfig.preset(providerEnum)
    llmConfig.modelName = liveConfig.model

    // Load API key: prefer EVAL_API_KEY env var, fall back to FileSecretStore
    if let envKey = ProcessInfo.processInfo.environment["EVAL_API_KEY"], !envKey.isEmpty {
        llmConfig.apiKey = envKey
    } else {
        let secretStore = FileSecretStore()
        if let storedKey = secretStore.load(key: "apiKey") {
            llmConfig.apiKey = storedKey
        }
    }

    return llmConfig
}

/// Convert FixtureInputFile.SignalsPayload → SessionSignals.
func signalsFromPayload(_ payload: FixtureInputFile.SignalsPayload) -> SessionSignals {
    var signals = SessionSignals(sessionID: payload.sessionID)
    signals.firstUserIntent = payload.firstUserIntent
    signals.lastUserIntent = payload.lastUserIntent
    signals.sampledUserIntents = payload.sampledUserIntents
    signals.lastAssistantProgress = payload.lastAssistantProgress
    signals.historyDisplayTexts = payload.historyDisplayTexts
    signals.versionMentions = payload.versionMentions
    signals.taskSubject = payload.taskSubject
    signals.taskDescription = payload.taskDescription
    signals.taskStatus = payload.taskStatus
    signals.entrypoint = payload.entrypoint
    signals.branch = payload.branch
    signals.slug = payload.slug
    signals.toolsUsed = Set(payload.toolsUsed)
    signals.filesModified = Set(payload.filesModified)
    signals.isSidechain = payload.isSidechain
    signals.turnCount = payload.turnCount
    signals.slashCommands = payload.slashCommands
    signals.commandErrors = payload.commandErrors
    signals.hasAssistantReply = payload.hasAssistantReply
    signals.totalEntryCount = payload.totalEntryCount
    signals.historyCount = payload.historyCount
    return signals
}

/// Build PromptBuilderHashInputs from current hasher knowledge.
func buildPromptHashInputs() -> RunArtifact.PromptBuilderHashInputs {
    return RunArtifact.PromptBuilderHashInputs(
        sourceFiles: [
            "Sources/ClaudeSessionHub/Services/LLMPrompts.swift",
            "Sources/ClaudeSessionHub/Services/SignalExtractor.swift"
        ],
        algorithm: "sha256"
    )
}
