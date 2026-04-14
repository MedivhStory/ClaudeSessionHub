// Sources/EvalHarnessCore/HarnessErrors.swift
import Foundation

public enum HarnessConfigError: Error, CustomStringConvertible, Sendable {
    case unpairedFixture(id: String, missing: PairSide)
    case schemaMissing(id: String, file: String)
    case schemaTooNew(id: String, found: String, supported: String)
    case malformedInput(id: String, reason: String)
    case malformedExpected(id: String, reason: String)
    case fixtureIDMismatch(prefix: String, inputID: String?, expectedID: String?)
    case invalidKindMetaCombination(id: String, reason: String)
    case invalidRegex(id: String, field: String, pattern: String, error: String)
    case invalidConstraintValue(id: String, field: String, constraint: String, reason: String)
    case verbatimMatchRequiresJustification(id: String, field: String, value: String, length: Int)
    case promptSourceMissing

    public var description: String {
        switch self {
        case .unpairedFixture(let id, let missing):
            return "fixture '\(id)': missing \(missing.rawValue) file"
        case .schemaMissing(let id, let file):
            return "fixture '\(id)' file '\(file)': schemaVersion field is missing"
        case .schemaTooNew(let id, let found, let supported):
            return "fixture '\(id)': schemaVersion '\(found)' is newer than harness support '\(supported)'. Upgrade the harness or downgrade the fixture."
        case .malformedInput(let id, let reason):
            return "fixture '\(id)' input.json is malformed: \(reason)"
        case .malformedExpected(let id, let reason):
            return "fixture '\(id)' expected.json is malformed: \(reason)"
        case .fixtureIDMismatch(let prefix, let inputID, let expectedID):
            return "fixture prefix '\(prefix)': id mismatch — input.id=\(inputID ?? "nil"), expected.id=\(expectedID ?? "nil"). All three must be equal."
        case .invalidKindMetaCombination(let id, let reason):
            return "fixture '\(id)': kind/meta invalid: \(reason)"
        case .invalidRegex(let id, let field, let pattern, let error):
            return "fixture '\(id)' field '\(field)': regex /\(pattern)/ failed to compile: \(error)"
        case .invalidConstraintValue(let id, let field, let constraint, let reason):
            return "fixture '\(id)' field '\(field)' constraint '\(constraint)': invalid value: \(reason)"
        case .verbatimMatchRequiresJustification(let id, let field, let value, let length):
            return "fixture '\(id)' field '\(field)': \(length)-char constraint string '\(String(value.prefix(40)))...' appears verbatim in input text. Add 'verbatimMatchJustification' field with a human-readable reason, or remove the verbatim copy."
        case .promptSourceMissing:
            return "GeneratedPromptSource constant is missing — build plugin failed silently. This should not be possible; investigate build pipeline."
        }
    }
}

public enum PairSide: String, Sendable {
    case input, expected
}

public enum GateCheckFailure: Error, CustomStringConvertible, Sendable {
    case noMatchingArtifact(tag: String, candidateSHA: String)
    case multipleMatchingArtifacts(tag: String, candidateSHA: String, matches: [String])
    case modeIsNotRelease(found: String)
    case providerMismatch(expected: String, found: String)
    case modelMismatch(expected: String, found: String)
    case temperatureMismatch(expected: Double, found: Double)
    case commitShaMismatch(expected: String, found: String)
    case promptBuilderHashMismatch(expected: String, found: String)
    case dslSchemaVersionMismatch(expected: String, found: String)
    case gateResultNotPass(found: String)

    public var description: String {
        switch self {
        case .noMatchingArtifact(let tag, let sha):
            return "No artifact in gate-runs/ matches tag='\(tag)', mode=release, commitSHA=\(sha)"
        case .multipleMatchingArtifacts(let tag, let sha, let matches):
            return "Multiple artifacts match tag='\(tag)', commitSHA=\(sha): \(matches.joined(separator: ", ")). Delete stale artifacts or pass --artifact <path>."
        case .modeIsNotRelease(let found):
            return "Artifact mode is '\(found)', expected 'release'"
        case .providerMismatch(let expected, let found):
            return "Artifact provider '\(found)' does not match canonical '\(expected)'"
        case .modelMismatch(let expected, let found):
            return "Artifact model '\(found)' does not match canonical '\(expected)'"
        case .temperatureMismatch(let expected, let found):
            return "Artifact temperature \(found) does not match canonical \(expected)"
        case .commitShaMismatch(let expected, let found):
            return "Artifact commitSHA '\(found)' does not match candidate '\(expected)'"
        case .promptBuilderHashMismatch(let expected, let found):
            return "Artifact promptBuilderHash '\(found)' does not match current '\(expected)'"
        case .dslSchemaVersionMismatch(let expected, let found):
            return "Artifact dslSchemaVersion '\(found)' does not match harness '\(expected)'"
        case .gateResultNotPass(let found):
            return "Artifact gateResult is '\(found)', expected 'PASS'"
        }
    }
}
