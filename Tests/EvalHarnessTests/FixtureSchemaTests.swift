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
            meta: FixtureInputFile.Meta(
                failureMode: "test-failure",
                description: "A test fixture for round-trip verification"
            ),
            input: FixtureInputFile.Input(
                signals: signals,
                rawTurns: ["user: Fix the parser bug", "assistant: Sure, let me look"],
                basedOnLastActiveAt: "2026-04-09T12:00:00Z"
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(fixture)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FixtureInputFile.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, fixture.schemaVersion)
        XCTAssertEqual(decoded.id, fixture.id)
        XCTAssertEqual(decoded.kind, .synthetic)
        XCTAssertEqual(decoded.meta.description, "A test fixture for round-trip verification")
        XCTAssertEqual(decoded.meta.failureMode, "test-failure")
        XCTAssertNil(decoded.meta.desensitizedAt)
        XCTAssertNil(decoded.meta.desensitizationScriptVersion)
        XCTAssertEqual(decoded.input.signals.sessionID, "test-session-001")
        XCTAssertEqual(decoded.input.signals.firstUserIntent, "Fix the parser bug")
        XCTAssertEqual(decoded.input.signals.sampledUserIntents, ["add logging", "refactor signals"])
        XCTAssertEqual(decoded.input.signals.turnCount, 12)
        XCTAssertTrue(decoded.input.signals.hasAssistantReply)
        XCTAssertEqual(decoded.input.rawTurns, ["user: Fix the parser bug", "assistant: Sure, let me look"])
        XCTAssertEqual(decoded.input.basedOnLastActiveAt, "2026-04-09T12:00:00Z")
    }

    func test_fixtureInputFile_realSnapshot_withMeta() throws {
        let fixture = FixtureInputFile(
            schemaVersion: "1",
            id: "snap-001",
            kind: .realSnapshot,
            meta: FixtureInputFile.Meta(
                failureMode: nil,
                description: "Real snapshot from production session",
                desensitizedAt: "2026-04-10T00:00:00Z",
                desensitizationScriptVersion: "1.0.0"
            ),
            input: FixtureInputFile.Input(
                signals: FixtureInputFile.SignalsPayload(sessionID: "sess-abc"),
                rawTurns: [],
                basedOnLastActiveAt: "2026-04-09T10:00:00Z"
            )
        )

        let data = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(FixtureInputFile.self, from: data)

        XCTAssertEqual(decoded.kind, .realSnapshot)
        XCTAssertEqual(decoded.meta.desensitizedAt, "2026-04-10T00:00:00Z")
        XCTAssertEqual(decoded.meta.desensitizationScriptVersion, "1.0.0")
        XCTAssertEqual(decoded.meta.description, "Real snapshot from production session")
        XCTAssertEqual(decoded.input.signals.sessionID, "sess-abc")
    }

    // MARK: - ExpectedConstraintsFile round-trip

    func test_expectedConstraintsFile_jsonRoundTrip() throws {
        let titleConstraints = FieldConstraints(
            mustContainAny: ["parser"],
            mustNotContain: ["bug"],
            mustNotEqual: ["Untitled"],
            minLength: 10,
            maxLength: 80,
            mustMatchRegex: "^[A-Z]"
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
        XCTAssertEqual(decoded.title?.minLength, 10)
        XCTAssertEqual(decoded.title?.maxLength, 80)
        XCTAssertEqual(decoded.title?.mustMatchRegex, "^[A-Z]")
        XCTAssertEqual(decoded.title?.mustContainAny, ["parser"])
        XCTAssertEqual(decoded.title?.mustNotContain, ["bug"])
        XCTAssertEqual(decoded.title?.mustNotEqual, ["Untitled"])
        XCTAssertNil(decoded.title?.mustContainAll)
        XCTAssertEqual(decoded.summary?.minLength, 50)
        XCTAssertEqual(decoded.summary?.maxLength, 500)
        XCTAssertNil(decoded.verbatimMatchJustification)
    }

    // MARK: - FieldConstraints all operators decodable

    func test_fieldConstraints_allOperatorsDecodable() throws {
        let json = """
        {
            "mustContainAny": ["keyword", "term"],
            "mustContainAll": ["required"],
            "mustNotContain": ["forbidden"],
            "mustNotEqual": ["bad value"],
            "mustNotBeEmpty": true,
            "minLength": 5,
            "maxLength": 100,
            "mustMatchRegex": "^[A-Z]",
            "maxRegexMatchCount": {"pattern": "\\\\b(TODO|FIXME)\\\\b", "n": 0}
        }
        """
        let data = json.data(using: .utf8)!
        let constraints = try JSONDecoder().decode(FieldConstraints.self, from: data)

        XCTAssertEqual(constraints.mustContainAny, ["keyword", "term"])
        XCTAssertEqual(constraints.mustContainAll, ["required"])
        XCTAssertEqual(constraints.mustNotContain, ["forbidden"])
        XCTAssertEqual(constraints.mustNotEqual, ["bad value"])
        XCTAssertEqual(constraints.mustNotBeEmpty, true)
        XCTAssertEqual(constraints.minLength, 5)
        XCTAssertEqual(constraints.maxLength, 100)
        XCTAssertEqual(constraints.mustMatchRegex, "^[A-Z]")
        XCTAssertNotNil(constraints.maxRegexMatchCount)
        XCTAssertEqual(constraints.maxRegexMatchCount?.n, 0)
    }
}
