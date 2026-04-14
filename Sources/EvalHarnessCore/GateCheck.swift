// Sources/EvalHarnessCore/GateCheck.swift
import Foundation

public enum GateCheck {
    /// Find the unique matching artifact in a directory.
    /// Strict unique match: exactly 1 artifact must match (tagLabel, mode=release, commitSHA).
    public static func findMatchingArtifact(
        in dir: URL,
        tag: String,
        candidateSHA: String
    ) throws -> (artifact: RunArtifact, path: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            throw GateCheckFailure.noMatchingArtifact(tag: tag, candidateSHA: candidateSHA)
        }

        let jsonFiles = contents.filter { $0.pathExtension == "json" }
        var matches: [(RunArtifact, URL)] = []

        for file in jsonFiles {
            guard let data = try? Data(contentsOf: file),
                  let artifact = try? JSONDecoder().decode(RunArtifact.self, from: data) else {
                continue
            }
            if artifact.tagLabel == tag &&
               artifact.mode == .release &&
               artifact.commitSHA == candidateSHA {
                matches.append((artifact, file))
            }
        }

        switch matches.count {
        case 0:
            throw GateCheckFailure.noMatchingArtifact(tag: tag, candidateSHA: candidateSHA)
        case 1:
            return matches[0]
        default:
            throw GateCheckFailure.multipleMatchingArtifacts(
                tag: tag,
                candidateSHA: candidateSHA,
                matches: matches.map { $0.1.lastPathComponent }
            )
        }
    }

    /// Verify an artifact passes all 8 binding checks.
    public static func verify(artifact: RunArtifact, currentPromptHash: String) throws {
        if artifact.mode != .release {
            throw GateCheckFailure.modeIsNotRelease(found: artifact.mode.rawValue)
        }
        if artifact.provider != CanonicalGate.provider {
            throw GateCheckFailure.providerMismatch(expected: CanonicalGate.provider, found: artifact.provider)
        }
        if artifact.model != CanonicalGate.model {
            throw GateCheckFailure.modelMismatch(expected: CanonicalGate.model, found: artifact.model)
        }
        if artifact.temperature != CanonicalGate.temperature {
            throw GateCheckFailure.temperatureMismatch(expected: CanonicalGate.temperature, found: artifact.temperature)
        }
        if artifact.promptBuilderHash != currentPromptHash {
            throw GateCheckFailure.promptBuilderHashMismatch(expected: currentPromptHash, found: artifact.promptBuilderHash)
        }
        if artifact.dslSchemaVersion != CanonicalGate.dslSchemaVersion {
            throw GateCheckFailure.dslSchemaVersionMismatch(expected: CanonicalGate.dslSchemaVersion, found: artifact.dslSchemaVersion)
        }
        if artifact.gateResult != .pass {
            throw GateCheckFailure.gateResultNotPass(found: artifact.gateResult.rawValue)
        }
    }
}
