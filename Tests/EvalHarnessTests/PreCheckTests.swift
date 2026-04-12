// Tests/EvalHarnessTests/PreCheckTests.swift
import XCTest
@testable import EvalHarnessCore

final class PreCheckTests: XCTestCase {

    // MARK: - Helpers

    private func makeInput(firstUserIntent: String? = nil) -> FixtureInputFile {
        FixtureInputFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "precheck-test",
            kind: .synthetic,
            meta: nil,
            signals: FixtureInputFile.SignalsPayload(
                sessionID: "s1",
                firstUserIntent: firstUserIntent
            )
        )
    }

    private func makeExpected(
        contains: String? = nil,
        justification: String? = nil
    ) -> ExpectedConstraintsFile {
        ExpectedConstraintsFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "precheck-test",
            title: FieldConstraints(
                contains: contains,
                verbatimMatchJustification: justification
            )
        )
    }

    // MARK: - Test 1: Short string (< 20) does NOT trigger

    func test_shortString_doesNotTrigger() {
        // 19 characters – just below threshold
        let shortString = String(repeating: "x", count: 19)
        let input = makeInput(firstUserIntent: shortString)
        let expected = makeExpected(contains: shortString)

        let errors = PreCheck.checkVerbatimMatches(input: input, expected: expected)

        XCTAssertTrue(errors.isEmpty,
            "Short string should not trigger verbatim warning, got: \(errors)")
    }

    // MARK: - Test 2: Long string without justification triggers

    func test_longString_withoutJustification_triggers() {
        // 20 characters – at threshold
        let longString = String(repeating: "a", count: 20)
        let input = makeInput(firstUserIntent: longString)
        let expected = makeExpected(contains: longString, justification: nil)

        let errors = PreCheck.checkVerbatimMatches(input: input, expected: expected)

        XCTAssertFalse(errors.isEmpty, "Long verbatim string without justification should produce error")
        let hasVerbatimError = errors.contains {
            if case .verbatimMatchRequiresJustification(_, _, _, _) = $0 { return true }
            return false
        }
        XCTAssertTrue(hasVerbatimError, "Expected .verbatimMatchRequiresJustification")
    }

    // MARK: - Test 3: Long string WITH justification passes

    func test_longString_withJustification_passes() {
        let longString = String(repeating: "b", count: 25)
        let input = makeInput(firstUserIntent: longString)
        let expected = makeExpected(
            contains: longString,
            justification: "Intentional: testing exact phrase"
        )

        let errors = PreCheck.checkVerbatimMatches(input: input, expected: expected)

        XCTAssertTrue(errors.isEmpty,
            "Long verbatim string WITH justification should not produce error, got: \(errors)")
    }

    // MARK: - Test 4: Exactly 20 grapheme clusters triggers

    func test_boundaryAtExactly20_triggers() {
        // Exactly verbatimThreshold characters
        let exactly20 = String(repeating: "z", count: PreCheck.verbatimThreshold)
        XCTAssertEqual(exactly20.count, 20)

        let input = makeInput(firstUserIntent: exactly20)
        let expected = makeExpected(contains: exactly20, justification: nil)

        let errors = PreCheck.checkVerbatimMatches(input: input, expected: expected)

        XCTAssertFalse(errors.isEmpty,
            "String at exactly verbatimThreshold (\(PreCheck.verbatimThreshold)) should trigger")
        let hasVerbatimError = errors.contains {
            if case .verbatimMatchRequiresJustification(_, _, _, let length) = $0 {
                return length == 20
            }
            return false
        }
        XCTAssertTrue(hasVerbatimError, "Error should report length == 20")
    }
}
