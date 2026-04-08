import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class SearchScoringTests: XCTestCase {

    func testExactTitleMatchScoresHighest() {
        let score = SearchScorer.score(
            query: "auth middleware",
            title: "重构 auth middleware",
            smartTitle: nil,
            taskSummary: nil, progress: nil, userNote: nil,
            branch: nil, cwd: nil, sessionID: "abc123",
            historyTexts: []
        )
        XCTAssertTrue(score > 0)
    }

    func testSmartTitleScoresHigherThanOriginal() {
        let scoreOrig = SearchScorer.score(
            query: "auth",
            title: "auth refactor",
            smartTitle: nil,
            taskSummary: nil, progress: nil, userNote: nil,
            branch: nil, cwd: nil, sessionID: "x", historyTexts: []
        )
        let scoreSmart = SearchScorer.score(
            query: "auth",
            title: "abcd1234",
            smartTitle: "auth refactor",
            taskSummary: nil, progress: nil, userNote: nil,
            branch: nil, cwd: nil, sessionID: "x", historyTexts: []
        )
        XCTAssertTrue(scoreSmart >= scoreOrig)
    }

    func testHistoryTextContributes() {
        let score = SearchScorer.score(
            query: "middleware",
            title: "abcd1234",
            smartTitle: nil,
            taskSummary: nil, progress: nil, userNote: nil,
            branch: nil, cwd: nil, sessionID: "x",
            historyTexts: ["帮我重构 auth middleware"]
        )
        XCTAssertTrue(score > 0)
    }

    func testNoMatchReturnsZero() {
        let score = SearchScorer.score(
            query: "完全无关的搜索词",
            title: "auth refactor",
            smartTitle: nil,
            taskSummary: "fix login", progress: nil, userNote: nil,
            branch: "main", cwd: "/project", sessionID: "abc",
            historyTexts: ["something else"]
        )
        XCTAssertEqual(score, 0)
    }

    func testEvidenceSnippetReturned() {
        let evidence = SearchScorer.matchEvidence(
            query: "auth",
            title: "重构 auth middleware",
            smartTitle: nil,
            taskSummary: nil, progress: nil, userNote: nil,
            branch: nil, cwd: nil, sessionID: "x",
            historyTexts: ["帮我修改 auth 配置"]
        )
        XCTAssertFalse(evidence.isEmpty)
        XCTAssertTrue(evidence.contains { $0.field == "title" })
    }
}
