import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMPromptsTests: XCTestCase {
    func test_titleSystemPrompt_doesNotContainHardVersionRequirement() {
        XCTAssertFalse(LLMPrompts.titleSystemPrompt.contains("必须包含该版本号"))
    }

    func test_titleSystemPrompt_containsSharedVersionClause() {
        XCTAssertTrue(LLMPrompts.titleSystemPrompt.contains("【版本号约束】"))
    }

    func test_progressSystemPrompt_containsSharedVersionClause() {
        XCTAssertTrue(LLMPrompts.progressSystemPrompt.contains("【版本号约束】"))
    }

    func test_summarySystemPrompt_containsSharedVersionClause() {
        XCTAssertTrue(LLMPrompts.summarySystemPrompt.contains("【版本号约束】"))
    }

    func test_versionClause_zeroDetectionBranch_appliesToAllFields() {
        for prompt in [LLMPrompts.titleSystemPrompt, LLMPrompts.progressSystemPrompt, LLMPrompts.summarySystemPrompt] {
            XCTAssertTrue(prompt.contains("本 session 未识别到任何版本号"), "missing zero-detection branch")
            XCTAssertTrue(prompt.contains("禁止"), "missing prohibition language")
        }
    }

    func test_titleInput_withVersions_injectsStructuredList() {
        var signals = SessionSignals(sessionID: "t1")
        signals.historyDisplayTexts = ["start"]
        signals.versionMentions = [
            VersionMention(raw: "v0.2.5", normalized: "0.2.5",
                           selectedSource: SourceRef(kind: .history, index: 0),
                           occurrenceCount: 2)
        ]
        let input = LLMPrompts.titleInput(from: signals)
        XCTAssertTrue(input.contains("识别到的版本号"), "expected structured version mention injection")
        XCTAssertTrue(input.contains("v0.2.5"))
        XCTAssertTrue(input.contains("出现 2 次"))
    }

    func test_titleInput_noVersions_injectsZeroDetectionLine() {
        var signals = SessionSignals(sessionID: "t2")
        signals.historyDisplayTexts = ["just work"]
        let input = LLMPrompts.titleInput(from: signals)
        XCTAssertTrue(input.contains("本 session 未识别到任何版本号"))
    }

    func test_titleInput_rendersMilestoneLabelsWithReasons() {
        var signals = SessionSignals(sessionID: "t3")
        signals.historyDisplayTexts = ["first", "middle", "last"]
        let input = LLMPrompts.titleInput(from: signals)
        XCTAssertTrue(input.contains("[首条]"))
        XCTAssertTrue(input.contains("[末条]"))
    }

    func test_titleInput_noInlineMilestoneKeywordFilter() {
        // Guard against accidental re-introduction of the old inline code
        let source = try! String(contentsOfFile: "Sources/ClaudeSessionHub/Services/LLMPrompts.swift", encoding: .utf8)
        XCTAssertFalse(source.contains("let milestoneKeywords"), "inline milestone keyword filter should be removed")
    }
}
