// Sources/EvalHarnessCore/Verifier.swift
import Foundation
import ClaudeSessionHubLib

// MARK: - Field

/// Output fields of an LLMUnderstandingSnapshot that can carry constraints.
public enum Field: String, Sendable, Codable {
    case title
    case progress
    case summary
}

// MARK: - ConstraintKind

/// Every constraint operator supported by the 9-operator engine.
public enum ConstraintKind: String, Sendable, Codable {
    case mustContainAny
    case mustContainAll
    case mustNotContain
    case mustNotEqual
    case mustNotBeEmpty
    case minLength
    case maxLength
    case mustMatchRegex
    case maxRegexMatchCount
}

// MARK: - Violation

/// A single constraint that was not satisfied.
public struct Violation: Sendable {
    /// The snapshot field where the violation occurred.
    public let field: Field
    /// Which constraint operator failed.
    public let constraint: ConstraintKind
    /// Human-readable description of what was expected.
    public let expected: String
    /// Actual output value or excerpt.
    public let actual: String

    public init(field: Field, constraint: ConstraintKind, expected: String, actual: String) {
        self.field = field
        self.constraint = constraint
        self.expected = expected
        self.actual = actual
    }
}

// MARK: - VerificationResult

/// The full result of verifying one fixture against one snapshot.
public struct VerificationResult: Sendable {
    public let fixtureID: String
    /// True iff `violations` is empty.
    public let passed: Bool
    /// Every constraint violation found.  Non-fail-fast: always contains ALL
    /// violations, not just the first.
    public let violations: [Violation]

    public init(fixtureID: String, passed: Bool, violations: [Violation]) {
        self.fixtureID = fixtureID
        self.passed = passed
        self.violations = violations
    }
}

// MARK: - Verifier

/// Evaluates an `LLMUnderstandingSnapshot` against an `ExpectedConstraintsFile`
/// using the 9-operator constraint engine (I-8, I-9).
public enum Verifier {

    /// Run all constraints on `snapshot` and return a structured result.
    ///
    /// - Parameter fixtureID: The fixture identifier, echoed into the result.
    /// - Parameter snapshot:  The LLM output to check.
    /// - Parameter expected:  The constraints to enforce.
    /// - Returns: A `VerificationResult` with all violations (non-fail-fast).
    public static func verify(
        fixtureID: String,
        snapshot: LLMUnderstandingSnapshot,
        expected: ExpectedConstraintsFile
    ) -> VerificationResult {

        var violations: [Violation] = []

        // Build field-value pairs.  Nil snapshot fields are treated as "".
        let fieldValues: [(Field, String, FieldConstraints?)] = [
            (.title,    snapshot.title,            expected.title),
            (.progress, snapshot.progress ?? "",   nil),         // no progress constraints defined
            (.summary,  snapshot.summary  ?? "",   expected.summary),
        ]

        for (field, value, constraintsOpt) in fieldValues {
            guard let fc = constraintsOpt else { continue }
            checkField(field: field, value: value, fc: fc, violations: &violations)
        }

        return VerificationResult(
            fixtureID: fixtureID,
            passed: violations.isEmpty,
            violations: violations
        )
    }

    // MARK: - Per-field check

    private static func checkField(
        field: Field,
        value: String,
        fc: FieldConstraints,
        violations: inout [Violation]
    ) {
        // 1. mustNotBeEmpty – triggered by empty string.
        //    We infer this is required when minLength > 0 OR any other constraint
        //    is set.  But the spec only lists mustNotBeEmpty as its own operator.
        //    FieldConstraints uses minLength for minimum; we treat minLength == 0
        //    explicitly as "allow empty".  The mustNotBeEmpty operator fires when
        //    minLength is set to any value > 0 AND value is "".
        //    Per spec, treat the presence of minLength > 0 as the gate for
        //    mustNotBeEmpty; the minLength operator itself is checked separately.
        if value.isEmpty {
            // mustNotBeEmpty: fire when any constraint implies non-empty presence.
            if let min = fc.minLength, min > 0 {
                violations.append(Violation(
                    field: field,
                    constraint: .mustNotBeEmpty,
                    expected: "field must not be empty (minLength=\(min))",
                    actual: "(empty)"
                ))
                // Don't bother checking other length constraints on empty.
                return
            }
        }

        // 2. minLength
        if let min = fc.minLength {
            let len = value.count
            if len < min {
                violations.append(Violation(
                    field: field,
                    constraint: .minLength,
                    expected: ">= \(min) characters",
                    actual: "\(len) characters: \"\(truncate(value))\""
                ))
            }
        }

        // 3. maxLength
        if let max = fc.maxLength {
            let len = value.count
            if len > max {
                violations.append(Violation(
                    field: field,
                    constraint: .maxLength,
                    expected: "<= \(max) characters",
                    actual: "\(len) characters: \"\(truncate(value))\""
                ))
            }
        }

        // 4. mustContainAny (maps to `contains` in FieldConstraints)
        if let needle = fc.contains {
            if !value.contains(needle) {
                violations.append(Violation(
                    field: field,
                    constraint: .mustContainAny,
                    expected: "must contain \"\(needle)\"",
                    actual: "\"\(truncate(value))\""
                ))
            }
        }

        // 5. mustNotContain
        if let needle = fc.notContains {
            if value.contains(needle) {
                violations.append(Violation(
                    field: field,
                    constraint: .mustNotContain,
                    expected: "must not contain \"\(needle)\"",
                    actual: "\"\(truncate(value))\""
                ))
            }
        }

        // 6. mustNotEqual
        if let forbidden = fc.notEquals {
            if value == forbidden {
                violations.append(Violation(
                    field: field,
                    constraint: .mustNotEqual,
                    expected: "must not equal \"\(forbidden)\"",
                    actual: "\"\(value)\""
                ))
            }
        }

        // 7. mustContainAll (maps to `equals` for exact match, treated as
        //    mustContainAll with one element).
        //    Per FieldConstraints schema, `equals` means exact equality.
        //    We map it to mustContainAll (closest semantic fit for the operator).
        if let exact = fc.equals {
            if value != exact {
                violations.append(Violation(
                    field: field,
                    constraint: .mustContainAll,
                    expected: "must equal \"\(exact)\"",
                    actual: "\"\(truncate(value))\""
                ))
            }
        }

        // 8. mustMatchRegex (maps to `matches`)
        if let pattern = fc.matches {
            if !regexMatches(pattern: pattern, in: value) {
                violations.append(Violation(
                    field: field,
                    constraint: .mustMatchRegex,
                    expected: "must match regex /\(pattern)/",
                    actual: "\"\(truncate(value))\""
                ))
            }
        }

        // 9. maxRegexMatchCount (maps to `notMatches` — fires when the pattern
        //    DOES match, i.e. match count > 0, meaning the max is 0).
        //    When `notMatches` is set we assert matchCount == 0.
        if let pattern = fc.notMatches {
            let count = regexMatchCount(pattern: pattern, in: value)
            if count > 0 {
                violations.append(Violation(
                    field: field,
                    constraint: .maxRegexMatchCount,
                    expected: "must not match regex /\(pattern)/ (max 0 matches)",
                    actual: "\(count) match(es) in \"\(truncate(value))\""
                ))
            }
        }
    }

    // MARK: - Regex helpers

    private static func regexMatches(pattern: String, in string: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }

    private static func regexMatchCount(pattern: String, in string: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(string.startIndex..., in: string)
        return regex.numberOfMatches(in: string, range: range)
    }

    // MARK: - Formatting

    private static func truncate(_ s: String, to limit: Int = 80) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }
}
