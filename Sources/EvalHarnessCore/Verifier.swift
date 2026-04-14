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
            (.progress, snapshot.progress ?? "",   expected.progress),
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
        // 1. mustNotBeEmpty — fires when flag is true and value (trimmed) is empty.
        //    Also fires when minLength > 0 and value is empty (backwards-compat path).
        if fc.mustNotBeEmpty == true && value.trimmingCharacters(in: .whitespaces).isEmpty {
            violations.append(Violation(
                field: field,
                constraint: .mustNotBeEmpty,
                expected: "field must not be empty",
                actual: "(empty)"
            ))
            // Don't run other length checks on an empty value when mustNotBeEmpty fires.
            return
        }

        // Backward-compatible mustNotBeEmpty trigger: minLength > 0 on empty value.
        if value.isEmpty {
            if let min = fc.minLength, min > 0 {
                violations.append(Violation(
                    field: field,
                    constraint: .mustNotBeEmpty,
                    expected: "field must not be empty (minLength=\(min))",
                    actual: "(empty)"
                ))
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

        // 4. mustContainAny — output must contain at least one of the listed substrings.
        if let needles = fc.mustContainAny, !needles.isEmpty {
            let found = needles.contains { value.contains($0) }
            if !found {
                violations.append(Violation(
                    field: field,
                    constraint: .mustContainAny,
                    expected: "must contain at least one of \(needles)",
                    actual: "\"\(truncate(value))\""
                ))
            }
        }

        // 5. mustContainAll — output must contain every listed substring.
        if let needles = fc.mustContainAll {
            for needle in needles {
                if !value.contains(needle) {
                    violations.append(Violation(
                        field: field,
                        constraint: .mustContainAll,
                        expected: "must contain \"\(needle)\"",
                        actual: "\"\(truncate(value))\""
                    ))
                }
            }
        }

        // 6. mustNotContain — output must NOT contain any of the listed substrings.
        if let needles = fc.mustNotContain {
            for needle in needles {
                if value.contains(needle) {
                    violations.append(Violation(
                        field: field,
                        constraint: .mustNotContain,
                        expected: "must not contain \"\(needle)\"",
                        actual: "\"\(truncate(value))\""
                    ))
                }
            }
        }

        // 7. mustNotEqual — output must NOT equal any of the listed strings.
        if let forbidden = fc.mustNotEqual {
            for s in forbidden {
                if value == s {
                    violations.append(Violation(
                        field: field,
                        constraint: .mustNotEqual,
                        expected: "must not equal \"\(s)\"",
                        actual: "\"\(value)\""
                    ))
                }
            }
        }

        // 8. mustMatchRegex — output must match the regex (at least one match).
        if let pattern = fc.mustMatchRegex {
            if !regexMatches(pattern: pattern, in: value) {
                violations.append(Violation(
                    field: field,
                    constraint: .mustMatchRegex,
                    expected: "must match regex /\(pattern)/",
                    actual: "\"\(truncate(value))\""
                ))
            }
        }

        // 9. maxRegexMatchCount — number of non-overlapping matches must be <= n.
        if let cc = fc.maxRegexMatchCount {
            let count = regexMatchCount(pattern: cc.pattern, in: value)
            if count > cc.n {
                violations.append(Violation(
                    field: field,
                    constraint: .maxRegexMatchCount,
                    expected: "regex /\(cc.pattern)/ must match at most \(cc.n) time(s)",
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
