// Tests/EvalHarnessTests/HarnessErrorsTests.swift
import XCTest
@testable import EvalHarnessCore

final class HarnessErrorsTests: XCTestCase {
    func test_unpairedFixture_description() {
        let e = HarnessConfigError.unpairedFixture(id: "foo", missing: .expected)
        XCTAssertTrue(e.description.contains("foo"))
        XCTAssertTrue(e.description.contains("expected"))
    }
    func test_schemaMissing_description() {
        let e = HarnessConfigError.schemaMissing(id: "bar", file: "bar.input.json")
        XCTAssertTrue(e.description.contains("bar"))
        XCTAssertTrue(e.description.contains("schemaVersion"))
    }
    func test_schemaTooNew_description() {
        let e = HarnessConfigError.schemaTooNew(id: "x", found: "2", supported: "1")
        XCTAssertTrue(e.description.contains("2"))
        XCTAssertTrue(e.description.contains("1"))
    }
    func test_malformedInput_description() {
        let e = HarnessConfigError.malformedInput(id: "x", reason: "bad json")
        XCTAssertTrue(e.description.contains("bad json"))
    }
    func test_malformedExpected_description() {
        let e = HarnessConfigError.malformedExpected(id: "x", reason: "missing field")
        XCTAssertTrue(e.description.contains("missing field"))
    }
    func test_fixtureIDMismatch_description() {
        let e = HarnessConfigError.fixtureIDMismatch(prefix: "a", inputID: "b", expectedID: "c")
        XCTAssertTrue(e.description.contains("a"))
        XCTAssertTrue(e.description.contains("b"))
    }
    func test_invalidKindMetaCombination_description() {
        let e = HarnessConfigError.invalidKindMetaCombination(id: "x", reason: "synthetic needs null")
        XCTAssertTrue(e.description.contains("synthetic"))
    }
    func test_invalidRegex_description() {
        let e = HarnessConfigError.invalidRegex(id: "x", field: "title", pattern: "[bad", error: "unmatched bracket")
        XCTAssertTrue(e.description.contains("[bad"))
    }
    func test_invalidConstraintValue_description() {
        let e = HarnessConfigError.invalidConstraintValue(id: "x", field: "title", constraint: "minLength", reason: "negative")
        XCTAssertTrue(e.description.contains("negative"))
    }
    func test_verbatimMatchRequiresJustification_description() {
        let e = HarnessConfigError.verbatimMatchRequiresJustification(id: "x", field: "title", value: "long string here repeated", length: 25)
        XCTAssertTrue(e.description.contains("25"))
    }
    func test_promptSourceMissing_description() {
        let e = HarnessConfigError.promptSourceMissing
        XCTAssertFalse(e.description.isEmpty)
    }
}

final class GateCheckFailureTests: XCTestCase {
    func test_noMatchingArtifact_description() {
        let e = GateCheckFailure.noMatchingArtifact(tag: "v0.2.8", candidateSHA: "abc123")
        XCTAssertTrue(e.description.contains("v0.2.8"))
    }
    func test_multipleMatchingArtifacts_description() {
        let e = GateCheckFailure.multipleMatchingArtifacts(tag: "v0.2.8", candidateSHA: "abc", matches: ["a.json", "b.json"])
        XCTAssertTrue(e.description.contains("a.json"))
    }
    func test_modeIsNotRelease_description() {
        let e = GateCheckFailure.modeIsNotRelease(found: "dev")
        XCTAssertTrue(e.description.contains("dev"))
    }
    func test_providerMismatch_description() {
        let e = GateCheckFailure.providerMismatch(expected: "dashscope", found: "openai")
        XCTAssertTrue(e.description.contains("openai"))
    }
    func test_commitShaMismatch_description() {
        let e = GateCheckFailure.commitShaMismatch(expected: "aaa", found: "bbb")
        XCTAssertTrue(e.description.contains("aaa"))
        XCTAssertTrue(e.description.contains("bbb"))
    }
    func test_promptBuilderHashMismatch_description() {
        let e = GateCheckFailure.promptBuilderHashMismatch(expected: "sha256:x", found: "sha256:y")
        XCTAssertTrue(e.description.contains("sha256:x"))
    }
    func test_gateResultNotPass_description() {
        let e = GateCheckFailure.gateResultNotPass(found: "FAIL")
        XCTAssertTrue(e.description.contains("FAIL"))
    }
}
