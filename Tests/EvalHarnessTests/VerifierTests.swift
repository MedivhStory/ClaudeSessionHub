// Tests/EvalHarnessTests/VerifierTests.swift
import XCTest
@testable import EvalHarnessCore
import ClaudeSessionHubLib

final class VerifierTests: XCTestCase {

    // MARK: - Helpers

    private let baseDate = Date(timeIntervalSince1970: 0)

    private func makeSnapshot(
        title: String = "Default Title",
        progress: String? = nil,
        summary: String? = nil
    ) -> LLMUnderstandingSnapshot {
        LLMUnderstandingSnapshot(
            sessionID: "test-session",
            title: title,
            progress: progress,
            summary: summary,
            modelName: "test-model",
            generatedAt: baseDate,
            basedOnLastActiveAt: baseDate
        )
    }

    private func makeExpected(title: FieldConstraints, summary: FieldConstraints? = nil) -> ExpectedConstraintsFile {
        ExpectedConstraintsFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "verifier-test",
            title: title,
            summary: summary
        )
    }

    // MARK: - mustContainAny

    func test_mustContainAny_pass() {
        let snapshot = makeSnapshot(title: "Fix the parser bug")
        let expected = makeExpected(title: FieldConstraints(mustContainAny: ["parser"]))
        let result = Verifier.verify(fixtureID: "t1", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func test_mustContainAny_fail() {
        let snapshot = makeSnapshot(title: "Refactor utils")
        let expected = makeExpected(title: FieldConstraints(mustContainAny: ["parser"]))
        let result = Verifier.verify(fixtureID: "t1", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustContainAny)
    }

    func test_mustContainAny_passWhenOneOfMultipleMatches() {
        let snapshot = makeSnapshot(title: "Refactor utils")
        let expected = makeExpected(title: FieldConstraints(mustContainAny: ["parser", "utils"]))
        let result = Verifier.verify(fixtureID: "t1b", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    // MARK: - mustNotContain

    func test_mustNotContain_pass() {
        let snapshot = makeSnapshot(title: "Clean implementation")
        let expected = makeExpected(title: FieldConstraints(mustNotContain: ["TODO"]))
        let result = Verifier.verify(fixtureID: "t2", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_mustNotContain_fail() {
        let snapshot = makeSnapshot(title: "TODO: fix this")
        let expected = makeExpected(title: FieldConstraints(mustNotContain: ["TODO"]))
        let result = Verifier.verify(fixtureID: "t2", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustNotContain)
    }

    // MARK: - mustNotEqual

    func test_mustNotEqual_pass() {
        let snapshot = makeSnapshot(title: "Good Title")
        let expected = makeExpected(title: FieldConstraints(mustNotEqual: ["Untitled"]))
        let result = Verifier.verify(fixtureID: "t3", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_mustNotEqual_fail() {
        let snapshot = makeSnapshot(title: "Untitled")
        let expected = makeExpected(title: FieldConstraints(mustNotEqual: ["Untitled"]))
        let result = Verifier.verify(fixtureID: "t3", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustNotEqual)
    }

    // MARK: - mustNotBeEmpty (direct flag)

    func test_mustNotBeEmpty_pass() {
        let snapshot = makeSnapshot(title: "Non-empty title")
        let expected = makeExpected(title: FieldConstraints(mustNotBeEmpty: true))
        let result = Verifier.verify(fixtureID: "t4", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_mustNotBeEmpty_fail_onEmptyTitle() {
        let snapshot = makeSnapshot(title: "")
        let expected = makeExpected(title: FieldConstraints(mustNotBeEmpty: true))
        let result = Verifier.verify(fixtureID: "t4", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustNotBeEmpty)
    }

    func test_mustNotBeEmpty_alsoTriggeredByMinLengthOnEmptyValue() {
        // Backward-compatible path: minLength > 0 on empty value triggers mustNotBeEmpty.
        let snapshot = makeSnapshot(title: "")
        let expected = makeExpected(title: FieldConstraints(minLength: 1))
        let result = Verifier.verify(fixtureID: "t4b", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustNotBeEmpty)
    }

    // MARK: - minLength

    func test_minLength_pass() {
        let snapshot = makeSnapshot(title: "Short")
        let expected = makeExpected(title: FieldConstraints(minLength: 3))
        let result = Verifier.verify(fixtureID: "t5", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_minLength_fail() {
        let snapshot = makeSnapshot(title: "Hi")
        let expected = makeExpected(title: FieldConstraints(minLength: 5))
        let result = Verifier.verify(fixtureID: "t5", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .minLength)
    }

    // MARK: - maxLength

    func test_maxLength_pass() {
        let snapshot = makeSnapshot(title: "Short title")
        let expected = makeExpected(title: FieldConstraints(maxLength: 80))
        let result = Verifier.verify(fixtureID: "t6", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_maxLength_fail() {
        let long = String(repeating: "x", count: 81)
        let snapshot = makeSnapshot(title: long)
        let expected = makeExpected(title: FieldConstraints(maxLength: 80))
        let result = Verifier.verify(fixtureID: "t6", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .maxLength)
    }

    // MARK: - mustMatchRegex

    func test_mustMatchRegex_pass() {
        let snapshot = makeSnapshot(title: "Add feature X")
        let expected = makeExpected(title: FieldConstraints(mustMatchRegex: "^[A-Z]"))
        let result = Verifier.verify(fixtureID: "t7", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_mustMatchRegex_fail() {
        let snapshot = makeSnapshot(title: "add feature x")
        let expected = makeExpected(title: FieldConstraints(mustMatchRegex: "^[A-Z]"))
        let result = Verifier.verify(fixtureID: "t7", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustMatchRegex)
    }

    // MARK: - maxRegexMatchCount

    func test_maxRegexMatchCount_pass_noMatches() {
        let snapshot = makeSnapshot(title: "Clean title with no forbidden words")
        let expected = makeExpected(title: FieldConstraints(
            maxRegexMatchCount: CountConstraint(pattern: "\\bTODO\\b", n: 0)
        ))
        let result = Verifier.verify(fixtureID: "t8", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_maxRegexMatchCount_fail_hasMatches() {
        let snapshot = makeSnapshot(title: "TODO: fix this TODO item")
        let expected = makeExpected(title: FieldConstraints(
            maxRegexMatchCount: CountConstraint(pattern: "\\bTODO\\b", n: 0)
        ))
        let result = Verifier.verify(fixtureID: "t8", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .maxRegexMatchCount)
    }

    func test_maxRegexMatchCount_pass_withinLimit() {
        // Allow up to 1 match — "TODO" appears once, so passes.
        let snapshot = makeSnapshot(title: "TODO: fix this")
        let expected = makeExpected(title: FieldConstraints(
            maxRegexMatchCount: CountConstraint(pattern: "\\bTODO\\b", n: 1)
        ))
        let result = Verifier.verify(fixtureID: "t8b", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    // MARK: - mustContainAll

    func test_mustContainAll_pass() {
        let snapshot = makeSnapshot(title: "Implement parser rewrite")
        let expected = makeExpected(title: FieldConstraints(mustContainAll: ["parser", "rewrite"]))
        let result = Verifier.verify(fixtureID: "t9", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_mustContainAll_fail_missingOne() {
        let snapshot = makeSnapshot(title: "Implement parser")
        let expected = makeExpected(title: FieldConstraints(mustContainAll: ["parser", "rewrite"]))
        let result = Verifier.verify(fixtureID: "t9", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.constraint, .mustContainAll)
    }

    // MARK: - Summary field constraints

    func test_summaryField_minLength_pass() {
        let snapshot = makeSnapshot(title: "Title", summary: "A longer summary text here.")
        let expected = makeExpected(
            title: FieldConstraints(),
            summary: FieldConstraints(minLength: 10)
        )
        let result = Verifier.verify(fixtureID: "t10", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed)
    }

    func test_summaryField_minLength_fail() {
        let snapshot = makeSnapshot(title: "Title", summary: "Short")
        let expected = makeExpected(
            title: FieldConstraints(),
            summary: FieldConstraints(minLength: 50)
        )
        let result = Verifier.verify(fixtureID: "t10", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        let summaryViolation = result.violations.first { $0.field == .summary }
        XCTAssertNotNil(summaryViolation)
        XCTAssertEqual(summaryViolation?.constraint, .minLength)
    }

    // MARK: - nil summary treated as empty string

    func test_nilSummary_treatedAsEmpty_triggersMinLength() {
        let snapshot = makeSnapshot(title: "Title", summary: nil)
        let expected = makeExpected(
            title: FieldConstraints(),
            summary: FieldConstraints(mustNotBeEmpty: true)
        )
        let result = Verifier.verify(fixtureID: "t11", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        let summaryViolation = result.violations.first { $0.field == .summary }
        XCTAssertNotNil(summaryViolation)
        XCTAssertEqual(summaryViolation?.constraint, .mustNotBeEmpty)
    }

    // MARK: - Multi-violation aggregation (non-fail-fast)

    func test_multipleViolations_areAllCollected() {
        // Title "bad" violates: minLength (too short), mustNotContain (has "bad"),
        // mustNotEqual (equals "bad"), mustMatchRegex (doesn't start with digit).
        let snapshot = makeSnapshot(title: "bad")
        let expected = makeExpected(title: FieldConstraints(
            mustNotContain: ["bad"],
            mustNotEqual: ["bad"],
            minLength: 10,
            mustMatchRegex: "^[0-9]"   // must start with digit — fails
        ))
        let result = Verifier.verify(fixtureID: "t12", snapshot: snapshot, expected: expected)
        XCTAssertFalse(result.passed)
        // Should have: minLength, mustNotContain, mustNotEqual, mustMatchRegex
        let constraints: [ConstraintKind] = result.violations.map { $0.constraint }
        XCTAssertGreaterThanOrEqual(result.violations.count, 3,
            "Expected at least 3 violations, got \(result.violations.count): \(constraints)")

        XCTAssertTrue(constraints.contains(.minLength), "Missing minLength violation")
        XCTAssertTrue(constraints.contains(.mustNotContain), "Missing mustNotContain violation")
        XCTAssertTrue(constraints.contains(.mustNotEqual), "Missing mustNotEqual violation")
        XCTAssertTrue(constraints.contains(.mustMatchRegex), "Missing mustMatchRegex violation")
    }

    // MARK: - fixtureID is echoed in result

    func test_fixtureID_isEchoedInResult() {
        let snapshot = makeSnapshot(title: "Some title")
        let expected = makeExpected(title: FieldConstraints())
        let result = Verifier.verify(fixtureID: "echo-id-test", snapshot: snapshot, expected: expected)
        XCTAssertEqual(result.fixtureID, "echo-id-test")
    }

    // MARK: - All constraints pass → passed == true, zero violations

    func test_allConstraintsPass_producesPassedResult() {
        let snapshot = makeSnapshot(title: "Implement parser rewrite", summary: "A detailed summary of the work done.")
        let expected = makeExpected(
            title: FieldConstraints(
                mustContainAny: ["parser"],
                mustNotContain: ["TODO"],
                mustNotEqual: ["Untitled"],
                minLength: 5,
                maxLength: 80,
                mustMatchRegex: "^[A-Z]"
            ),
            summary: FieldConstraints(minLength: 10, maxLength: 200)
        )
        let result = Verifier.verify(fixtureID: "all-pass", snapshot: snapshot, expected: expected)
        XCTAssertTrue(result.passed, "Expected all constraints to pass, violations: \(result.violations)")
        XCTAssertEqual(result.violations.count, 0)
    }
}
