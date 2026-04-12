// Sources/EvalHarnessCore/FixtureLoader.swift
import Foundation

// MARK: - FixturePair

/// A validated, paired input+expected fixture ready for evaluation.
public struct FixturePair: Sendable {
    public let id: String
    public let input: FixtureInputFile
    public let expected: ExpectedConstraintsFile

    public init(id: String, input: FixtureInputFile, expected: ExpectedConstraintsFile) {
        self.id = id
        self.input = input
        self.expected = expected
    }
}

// MARK: - FixtureLoader

/// Loads fixture pairs from a directory and runs all validation stages,
/// aggregating errors without fail-fast behaviour (I-8).
public enum FixtureLoader {

    /// Scan `directory` for `*.input.json` / `*.expected.json` pairs, validate
    /// them through 8 stages, and return both valid pairs and all errors found.
    ///
    /// - Returns: `(pairs, errors)` – valid pairs AND any errors collected.
    ///   All stages run for every file; the function never returns early on the
    ///   first error.
    public static func loadAndValidate(
        directory: URL
    ) -> (pairs: [FixturePair], errors: [HarnessConfigError]) {

        var errors: [HarnessConfigError] = []
        var pairs: [FixturePair] = []

        // ── Stage 1: File pairing ──────────────────────────────────────────
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            // Nothing we can validate if directory is unreadable.
            return (pairs: [], errors: [])
        }

        var inputFiles: [String: URL] = [:]   // prefix → URL
        var expectedFiles: [String: URL] = [:] // prefix → URL

        for url in contents {
            let name = url.lastPathComponent
            if name.hasSuffix(".input.json") {
                let prefix = String(name.dropLast(".input.json".count))
                inputFiles[prefix] = url
            } else if name.hasSuffix(".expected.json") {
                let prefix = String(name.dropLast(".expected.json".count))
                expectedFiles[prefix] = url
            }
        }

        let allPrefixes = Set(inputFiles.keys).union(expectedFiles.keys)

        for prefix in allPrefixes.sorted() {
            let hasInput    = inputFiles[prefix] != nil
            let hasExpected = expectedFiles[prefix] != nil

            if !hasInput {
                errors.append(.unpairedFixture(id: prefix, missing: .input))
            }
            if !hasExpected {
                errors.append(.unpairedFixture(id: prefix, missing: .expected))
            }
        }

        // Only process fully paired prefixes from here on.
        let pairedPrefixes = allPrefixes.filter {
            inputFiles[$0] != nil && expectedFiles[$0] != nil
        }.sorted()

        let decoder = JSONDecoder()

        for prefix in pairedPrefixes {
            let inputURL    = inputFiles[prefix]!
            let expectedURL = expectedFiles[prefix]!

            // ── Stage 2: JSON decode ─────────────────────────────────────
            let inputData: Data
            let expectedData: Data

            do { inputData    = try Data(contentsOf: inputURL) }
            catch { errors.append(.malformedInput(id: prefix, reason: error.localizedDescription)); continue }

            do { expectedData = try Data(contentsOf: expectedURL) }
            catch { errors.append(.malformedExpected(id: prefix, reason: error.localizedDescription)); continue }

            let input: FixtureInputFile
            let expected: ExpectedConstraintsFile

            do { input    = try decoder.decode(FixtureInputFile.self, from: inputData) }
            catch { errors.append(.malformedInput(id: prefix, reason: "\(error)")); continue }

            do { expected = try decoder.decode(ExpectedConstraintsFile.self, from: expectedData) }
            catch { errors.append(.malformedExpected(id: prefix, reason: "\(error)")); continue }

            // Collect per-fixture errors without early-exiting.
            var fixtureErrors: [HarnessConfigError] = []

            // ── Stage 3: Schema version ──────────────────────────────────
            let supported = CanonicalGate.dslSchemaVersion

            if input.schemaVersion.isEmpty {
                fixtureErrors.append(.schemaMissing(id: prefix, file: "\(prefix).input.json"))
            } else if schemaVersion(input.schemaVersion, isNewerThan: supported) {
                fixtureErrors.append(.schemaTooNew(
                    id: prefix, found: input.schemaVersion, supported: supported))
            }

            if expected.schemaVersion.isEmpty {
                fixtureErrors.append(.schemaMissing(id: prefix, file: "\(prefix).expected.json"))
            } else if schemaVersion(expected.schemaVersion, isNewerThan: supported) {
                fixtureErrors.append(.schemaTooNew(
                    id: prefix, found: expected.schemaVersion, supported: supported))
            }

            // ── Stage 4: Three-way ID check (I-6) ───────────────────────
            if prefix != input.id || input.id != expected.id {
                fixtureErrors.append(.fixtureIDMismatch(
                    prefix: prefix,
                    inputID: input.id,
                    expectedID: expected.id
                ))
            }

            // ── Stage 5: Kind / Meta ─────────────────────────────────────
            switch input.kind {
            case .synthetic:
                if let meta = input.meta {
                    if meta.sessionID != nil || meta.capturedAt != nil {
                        fixtureErrors.append(.invalidKindMetaCombination(
                            id: prefix,
                            reason: "synthetic fixture must not have desensitized meta fields (sessionID, capturedAt)"))
                    }
                }
            case .realSnapshot:
                if input.meta == nil {
                    fixtureErrors.append(.invalidKindMetaCombination(
                        id: prefix,
                        reason: "real-snapshot fixture must supply a non-nil meta block"))
                } else if let meta = input.meta, meta.sessionID == nil && meta.capturedAt == nil {
                    fixtureErrors.append(.invalidKindMetaCombination(
                        id: prefix,
                        reason: "real-snapshot fixture must have at least one non-null meta field"))
                }
            }

            // ── Stage 6: Regex compilability ────────────────────────────
            let allFieldConstraints: [(String, FieldConstraints)] = [
                ("title", expected.title)
            ] + (expected.summary.map { [("summary", $0)] } ?? [])

            for (fieldName, fc) in allFieldConstraints {
                if let pattern = fc.matches {
                    validateRegex(pattern: pattern, id: prefix, field: fieldName,
                                  errors: &fixtureErrors)
                }
                if let pattern = fc.notMatches {
                    validateRegex(pattern: pattern, id: prefix, field: fieldName,
                                  errors: &fixtureErrors)
                }
            }

            // ── Stage 7: Constraint values ───────────────────────────────
            for (fieldName, fc) in allFieldConstraints {
                if let min = fc.minLength, min < 0 {
                    fixtureErrors.append(.invalidConstraintValue(
                        id: prefix, field: fieldName, constraint: "minLength",
                        reason: "value \(min) must be >= 0"))
                }
                if let max = fc.maxLength, max < 0 {
                    fixtureErrors.append(.invalidConstraintValue(
                        id: prefix, field: fieldName, constraint: "maxLength",
                        reason: "value \(max) must be >= 0"))
                }
                if let min = fc.minLength, let max = fc.maxLength, min > max {
                    fixtureErrors.append(.invalidConstraintValue(
                        id: prefix, field: fieldName, constraint: "minLength/maxLength",
                        reason: "minLength \(min) must be <= maxLength \(max)"))
                }
            }

            // ── Stage 8: PreCheck (verbatim heuristic) ───────────────────
            let preCheckErrors = PreCheck.checkVerbatimMatches(input: input, expected: expected)
            fixtureErrors.append(contentsOf: preCheckErrors)

            errors.append(contentsOf: fixtureErrors)

            // Only accumulate a valid pair if this fixture had no errors.
            if fixtureErrors.isEmpty {
                pairs.append(FixturePair(id: prefix, input: input, expected: expected))
            }
        }

        return (pairs: pairs, errors: errors)
    }

    // MARK: - Helpers

    /// Returns true if `found` is strictly newer than `supported`.
    /// Compares by integer value; non-integer versions are treated as newer.
    private static func schemaVersion(_ found: String, isNewerThan supported: String) -> Bool {
        if let f = Int(found), let s = Int(supported) {
            return f > s
        }
        // Non-numeric: treat as newer (fail-safe).
        return found != supported
    }

    private static func validateRegex(
        pattern: String,
        id: String,
        field: String,
        errors: inout [HarnessConfigError]
    ) {
        do {
            _ = try NSRegularExpression(pattern: pattern)
        } catch {
            errors.append(.invalidRegex(
                id: id, field: field, pattern: pattern, error: error.localizedDescription))
        }
    }
}
