import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class VersionMentionExtractorTests: XCTestCase {

    private func makeSignals(
        history: [String] = [],
        firstUserIntent: String? = nil,
        lastUserIntent: String? = nil,
        lastAssistantProgress: String? = nil,
        taskSubject: String? = nil,
        taskDescription: String? = nil
    ) -> SessionSignals {
        var s = SessionSignals(sessionID: "test")
        s.historyDisplayTexts = history
        s.firstUserIntent = firstUserIntent
        s.lastUserIntent = lastUserIntent
        s.lastAssistantProgress = lastAssistantProgress
        s.taskSubject = taskSubject
        s.taskDescription = taskDescription
        return s
    }

    func test_strictSemver_matches_valid() {
        let s = makeSignals(history: ["initial v0.2.5 release", "0.2.5 patch", "V0.2.5 retry"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].normalized, "0.2.5")
        XCTAssertEqual(result[0].occurrenceCount, 3)
    }

    func test_strictSemver_withPrerelease() {
        let s = makeSignals(history: ["testing v1.0.0-rc.1"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result.first?.normalized.hasPrefix("1.0.0"), true)
    }

    func test_strictSemver_rejectsNonSemver() {
        let s = makeSignals(history: ["v2 shipped", "2024.Q3 was good", "foo.bar"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertTrue(result.isEmpty, "got \(result)")
    }

    func test_normalization_stripVPrefix() {
        let s = makeSignals(history: ["v0.2.5 and 0.2.5 and V0.2.5"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].normalized, "0.2.5")
    }

    func test_rawPreservesFirstEncounter() {
        let s = makeSignals(history: ["V0.2.5 first", "v0.2.5 second"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result[0].raw, "V0.2.5")
    }

    func test_occurrenceCount_countsAcrossSources() {
        let s = makeSignals(
            history: ["v0.2.5", "v0.2.5 again"],
            firstUserIntent: "working on v0.2.5"
        )
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result[0].occurrenceCount, 3)
    }

    func test_selectedSource_scanOrderPriority_taskSubjectWins() {
        let s = makeSignals(
            history: ["v0.2.5 in history"],
            firstUserIntent: "v0.2.5 in intent",
            taskSubject: "v0.2.5 in task"
        )
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result[0].selectedSource.kind, .taskSubject)
        XCTAssertNil(result[0].selectedSource.index)
    }

    func test_selectedSource_historyKind_carriesIndex() {
        let s = makeSignals(history: ["something else", "v0.2.5 here"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result[0].selectedSource.kind, .history)
        XCTAssertEqual(result[0].selectedSource.index, 1)
    }

    func test_allSixSources_scanned() {
        // Each source contributes a distinct version.
        let s = makeSignals(
            history: ["v0.5.0"],
            firstUserIntent: "v0.2.0",
            lastUserIntent: "v0.3.0",
            lastAssistantProgress: "v0.6.0",
            taskSubject: "v0.1.0",
            taskDescription: "v0.4.0"
        )
        let result = VersionMentionExtractor.extract(from: s)
        let normalizeds = Set(result.map { $0.normalized })
        XCTAssertEqual(normalizeds, Set(["0.1.0", "0.2.0", "0.3.0", "0.4.0", "0.5.0", "0.6.0"]))
    }

    func test_deterministicSort_tiebreaker() {
        // Two versions, both selectedSource in history. Sort by (scanOrder asc, count desc, normalized asc).
        let s = makeSignals(history: ["v0.2.6", "v0.2.5"])
        let result = VersionMentionExtractor.extract(from: s)
        XCTAssertEqual(result.map { $0.normalized }, ["0.2.5", "0.2.6"])
    }

    func test_emptyInput_returnsEmpty() {
        let result = VersionMentionExtractor.extract(from: makeSignals())
        XCTAssertTrue(result.isEmpty)
    }
}
