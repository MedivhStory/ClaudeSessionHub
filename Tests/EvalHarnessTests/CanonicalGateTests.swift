// Tests/EvalHarnessTests/CanonicalGateTests.swift
import XCTest
@testable import EvalHarnessCore

final class CanonicalGateTests: XCTestCase {
    func test_canonicalConstants_matchSpec() {
        XCTAssertEqual(CanonicalGate.provider, "dashscope")
        XCTAssertEqual(CanonicalGate.model, "qwen-plus")
        XCTAssertEqual(CanonicalGate.temperature, 0.0)
        XCTAssertEqual(CanonicalGate.dslSchemaVersion, "1")
    }
}
