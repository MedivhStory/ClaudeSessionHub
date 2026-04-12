// Tests/EvalHarnessTests/FixtureLoaderTests.swift
import XCTest
@testable import EvalHarnessCore

final class FixtureLoaderTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func writeJSON<T: Encodable>(_ value: T, to dir: URL, name: String) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: dir.appendingPathComponent(name))
    }

    /// Minimal valid input file.
    private func makeInput(id: String, kind: FixtureInputFile.Kind = .synthetic) -> FixtureInputFile {
        FixtureInputFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: id,
            kind: kind,
            meta: kind == .realSnapshot
                ? FixtureInputFile.Meta(sessionID: "sess-\(id)", capturedAt: "2026-01-01")
                : nil,
            signals: FixtureInputFile.SignalsPayload(sessionID: "sess-\(id)")
        )
    }

    /// Minimal valid expected file.
    private func makeExpected(id: String) -> ExpectedConstraintsFile {
        ExpectedConstraintsFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: id,
            title: FieldConstraints(minLength: 5, maxLength: 80)
        )
    }

    // MARK: - Test 1: Valid pair loads successfully

    func test_validPair_loadsAndReturnsNoErrors() throws {
        let dir = try makeTempDir()
        try writeJSON(makeInput(id: "fix-001"), to: dir, name: "fix-001.input.json")
        try writeJSON(makeExpected(id: "fix-001"), to: dir, name: "fix-001.expected.json")

        let result = FixtureLoader.loadAndValidate(directory: dir)

        XCTAssertEqual(result.errors.count, 0, "Expected no errors, got: \(result.errors)")
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertEqual(result.pairs.first?.id, "fix-001")
    }

    // MARK: - Test 2: Unpaired input (no expected) → error

    func test_unpairedInput_producesUnpairedError() throws {
        let dir = try makeTempDir()
        try writeJSON(makeInput(id: "orphan"), to: dir, name: "orphan.input.json")
        // no orphan.expected.json

        let result = FixtureLoader.loadAndValidate(directory: dir)

        XCTAssertEqual(result.pairs.count, 0)
        let hasMissingExpected = result.errors.contains {
            if case .unpairedFixture(let id, let side) = $0 {
                return id == "orphan" && side == .expected
            }
            return false
        }
        XCTAssertTrue(hasMissingExpected, "Expected .unpairedFixture(id:orphan, missing:.expected)")
    }

    // MARK: - Test 3: schemaMissing when schemaVersion is empty

    func test_schemaMissing_whenSchemaVersionEmpty() throws {
        let dir = try makeTempDir()
        // Write raw JSON with empty schemaVersion
        let inputJSON = """
        {
            "schemaVersion": "",
            "id": "empty-schema",
            "kind": "synthetic",
            "signals": {
                "sessionID": "s1",
                "sampledUserIntents": [],
                "historyDisplayTexts": [],
                "versionMentions": [],
                "toolsUsed": [],
                "filesModified": [],
                "isSidechain": false,
                "turnCount": 0,
                "slashCommands": [],
                "commandErrors": [],
                "hasAssistantReply": false,
                "totalEntryCount": 0,
                "historyCount": 0
            }
        }
        """
        try inputJSON.data(using: .utf8)!
            .write(to: dir.appendingPathComponent("empty-schema.input.json"))
        try writeJSON(makeExpected(id: "empty-schema"), to: dir, name: "empty-schema.expected.json")

        let result = FixtureLoader.loadAndValidate(directory: dir)

        let hasSchemaMissing = result.errors.contains {
            if case .schemaMissing(let id, _) = $0 { return id == "empty-schema" }
            return false
        }
        XCTAssertTrue(hasSchemaMissing, "Expected .schemaMissing error")
    }

    // MARK: - Test 4: schemaTooNew when version is newer

    func test_schemaTooNew_whenVersionNewerThanSupported() throws {
        let dir = try makeTempDir()
        // Write raw JSON with a future schemaVersion
        let inputJSON = """
        {
            "schemaVersion": "999",
            "id": "future-schema",
            "kind": "synthetic",
            "signals": {
                "sessionID": "s1",
                "sampledUserIntents": [],
                "historyDisplayTexts": [],
                "versionMentions": [],
                "toolsUsed": [],
                "filesModified": [],
                "isSidechain": false,
                "turnCount": 0,
                "slashCommands": [],
                "commandErrors": [],
                "hasAssistantReply": false,
                "totalEntryCount": 0,
                "historyCount": 0
            }
        }
        """
        try inputJSON.data(using: .utf8)!
            .write(to: dir.appendingPathComponent("future-schema.input.json"))
        try writeJSON(makeExpected(id: "future-schema"), to: dir, name: "future-schema.expected.json")

        let result = FixtureLoader.loadAndValidate(directory: dir)

        let hasSchemaTooNew = result.errors.contains {
            if case .schemaTooNew(let id, _, _) = $0 { return id == "future-schema" }
            return false
        }
        XCTAssertTrue(hasSchemaTooNew, "Expected .schemaTooNew error")
    }

    // MARK: - Test 5: fixtureIDMismatch

    func test_fixtureIDMismatch_whenIDsDoNotMatch() throws {
        let dir = try makeTempDir()
        // Prefix is "mismatch-fix", but input.id = "wrong-id"
        let input = FixtureInputFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "wrong-id",
            kind: .synthetic,
            meta: nil,
            signals: FixtureInputFile.SignalsPayload(sessionID: "s1")
        )
        try writeJSON(input, to: dir, name: "mismatch-fix.input.json")
        try writeJSON(makeExpected(id: "mismatch-fix"), to: dir, name: "mismatch-fix.expected.json")

        let result = FixtureLoader.loadAndValidate(directory: dir)

        let hasMismatch = result.errors.contains {
            if case .fixtureIDMismatch(let prefix, _, _) = $0 { return prefix == "mismatch-fix" }
            return false
        }
        XCTAssertTrue(hasMismatch, "Expected .fixtureIDMismatch error")
        XCTAssertEqual(result.pairs.count, 0)
    }

    // MARK: - Test 6: invalidRegex

    func test_invalidRegex_forBadPattern() throws {
        let dir = try makeTempDir()
        try writeJSON(makeInput(id: "regex-fix"), to: dir, name: "regex-fix.input.json")
        // Bad regex in title.matches
        let expected = ExpectedConstraintsFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "regex-fix",
            title: FieldConstraints(matches: "[invalid(")
        )
        try writeJSON(expected, to: dir, name: "regex-fix.expected.json")

        let result = FixtureLoader.loadAndValidate(directory: dir)

        let hasInvalidRegex = result.errors.contains {
            if case .invalidRegex(let id, _, _, _) = $0 { return id == "regex-fix" }
            return false
        }
        XCTAssertTrue(hasInvalidRegex, "Expected .invalidRegex error, got: \(result.errors)")
    }

    // MARK: - Test 7: Multiple errors aggregate (non-fail-fast)

    func test_multipleFixtures_aggregatesAllErrors_nonFailFast() throws {
        let dir = try makeTempDir()

        // Fixture A: unpaired (only input)
        try writeJSON(makeInput(id: "a"), to: dir, name: "a.input.json")

        // Fixture B: bad regex
        try writeJSON(makeInput(id: "b"), to: dir, name: "b.input.json")
        let expectedB = ExpectedConstraintsFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "b",
            title: FieldConstraints(matches: "[bad(")
        )
        try writeJSON(expectedB, to: dir, name: "b.expected.json")

        // Fixture C: ID mismatch
        let inputC = FixtureInputFile(
            schemaVersion: CanonicalGate.dslSchemaVersion,
            id: "c-wrong",
            kind: .synthetic,
            meta: nil,
            signals: FixtureInputFile.SignalsPayload(sessionID: "s3")
        )
        try writeJSON(inputC, to: dir, name: "c.input.json")
        try writeJSON(makeExpected(id: "c"), to: dir, name: "c.expected.json")

        let result = FixtureLoader.loadAndValidate(directory: dir)

        // Should have errors from all three fixtures.
        XCTAssertGreaterThanOrEqual(result.errors.count, 3,
            "Expected >= 3 errors (one per bad fixture), got \(result.errors.count): \(result.errors)")

        let hasUnpaired = result.errors.contains {
            if case .unpairedFixture(let id, _) = $0 { return id == "a" }
            return false
        }
        let hasInvalidRegex = result.errors.contains {
            if case .invalidRegex(let id, _, _, _) = $0 { return id == "b" }
            return false
        }
        let hasMismatch = result.errors.contains {
            if case .fixtureIDMismatch(let prefix, _, _) = $0 { return prefix == "c" }
            return false
        }
        XCTAssertTrue(hasUnpaired,      "Missing unpairedFixture(a) error")
        XCTAssertTrue(hasInvalidRegex,  "Missing invalidRegex(b) error")
        XCTAssertTrue(hasMismatch,      "Missing fixtureIDMismatch(c) error")
    }
}
