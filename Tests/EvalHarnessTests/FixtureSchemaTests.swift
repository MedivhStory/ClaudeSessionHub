// Tests/EvalHarnessTests/FixtureSchemaTests.swift
import XCTest
@testable import EvalHarnessCore

final class FixtureSchemaTests: XCTestCase {

    // MARK: - FixtureInputFile round-trip

    func test_fixtureInputFile_jsonRoundTrip() throws {
        let signals = FixtureInputFile.SignalsPayload(
            sessionID: "test-session-001",
            firstUserIntent: "Fix the parser bug",
            lastUserIntent: "Run the tests",
            sampledUserIntents: ["add logging", "refactor signals"],
            lastAssistantProgress: "Tests are passing",
            historyDisplayTexts: ["Session history line 1"],
            versionMentions: [],
            taskSubject: "Parser rewrite",
            taskDescription: "Rewrite the parser module",
            taskStatus: "in-progress",
            entrypoint: "/projects/myapp",
            branch: "feature/parser",
            slug: "parser-rewrite",
            toolsUsed: ["Bash", "Edit"],
            filesModified: ["Sources/Parser.swift"],
            isSidechain: false,
            turnCount: 12,
            slashCommands: [],
            commandErrors: [],
            hasAssistantReply: true,
            totalEntryCount: 100,
            historyCount: 5
        )
        let fixture = FixtureInputFile(
            schemaVersion: "1",
            id: "test-fixture-001",
            kind: .synthetic,
            meta: nil,
            signals: signals
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(fixture)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FixtureInputFile.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, fixture.schemaVersion)
        XCTAssertEqual(decoded.id, fixture.id)
        XCTAssertEqual(decoded.kind, .synthetic)
        XCTAssertNil(decoded.meta)
        XCTAssertEqual(decoded.signals.sessionID, "test-session-001")
        XCTAssertEqual(decoded.signals.firstUserIntent, "Fix the parser bug")
        XCTAssertEqual(decoded.signals.sampledUserIntents, ["add logging", "refactor signals"])
        XCTAssertEqual(decoded.signals.turnCount, 12)
        XCTAssertTrue(decoded.signals.hasAssistantReply)
    }

    func test_fixtureInputFile_realSnapshot_withMeta() throws {
        let fixture = FixtureInputFile(
            schemaVersion: "1",
            id: "snap-001",
            kind: .realSnapshot,
            meta: FixtureInputFile.Meta(sessionID: "sess-abc", capturedAt: "2026-04-10T00:00:00Z"),
            signals: FixtureInputFile.SignalsPayload(sessionID: "sess-abc")
        )

        let data = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(FixtureInputFile.self, from: data)

        XCTAssertEqual(decoded.kind, .realSnapshot)
        XCTAssertEqual(decoded.meta?.sessionID, "sess-abc")
        XCTAssertEqual(decoded.meta?.capturedAt, "2026-04-10T00:00:00Z")
    }

    // MARK: - ExpectedConstraintsFile round-trip

    func test_expectedConstraintsFile_jsonRoundTrip() throws {
        let titleConstraints = FieldConstraints(
            minLength: 10,
            maxLength: 80,
            matches: "^[A-Z]",
            notMatches: "TODO",
            contains: "parser",
            notContains: "bug",
            equals: nil,
            notEquals: "Untitled",
            verbatimMatchJustification: nil
        )
        let summaryConstraints = FieldConstraints(
            minLength: 50,
            maxLength: 500
        )
        let expected = ExpectedConstraintsFile(
            schemaVersion: "1",
            id: "test-fixture-001",
            title: titleConstraints,
            summary: summaryConstraints
        )

        let data = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(ExpectedConstraintsFile.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, "1")
        XCTAssertEqual(decoded.id, "test-fixture-001")
        XCTAssertEqual(decoded.title.minLength, 10)
        XCTAssertEqual(decoded.title.maxLength, 80)
        XCTAssertEqual(decoded.title.matches, "^[A-Z]")
        XCTAssertEqual(decoded.title.notMatches, "TODO")
        XCTAssertEqual(decoded.title.contains, "parser")
        XCTAssertEqual(decoded.title.notContains, "bug")
        XCTAssertNil(decoded.title.equals)
        XCTAssertEqual(decoded.title.notEquals, "Untitled")
        XCTAssertEqual(decoded.summary?.minLength, 50)
        XCTAssertEqual(decoded.summary?.maxLength, 500)
    }

    // MARK: - FieldConstraints all operators decodable

    func test_fieldConstraints_allOperatorsDecodable() throws {
        let json = """
        {
            "minLength": 5,
            "maxLength": 100,
            "matches": "^[A-Z]",
            "notMatches": "\\\\b(TODO|FIXME)\\\\b",
            "contains": "keyword",
            "notContains": "forbidden",
            "equals": "exact value",
            "notEquals": "bad value",
            "verbatimMatchJustification": "This is intentional"
        }
        """
        let data = json.data(using: .utf8)!
        let constraints = try JSONDecoder().decode(FieldConstraints.self, from: data)

        XCTAssertEqual(constraints.minLength, 5)
        XCTAssertEqual(constraints.maxLength, 100)
        XCTAssertEqual(constraints.matches, "^[A-Z]")
        XCTAssertNotNil(constraints.notMatches)
        XCTAssertEqual(constraints.contains, "keyword")
        XCTAssertEqual(constraints.notContains, "forbidden")
        XCTAssertEqual(constraints.equals, "exact value")
        XCTAssertEqual(constraints.notEquals, "bad value")
        XCTAssertEqual(constraints.verbatimMatchJustification, "This is intentional")
    }
}
