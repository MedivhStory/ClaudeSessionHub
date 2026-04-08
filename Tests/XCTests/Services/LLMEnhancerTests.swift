import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMEnhancerTests: XCTestCase {

    func testPromptInputContainsSignals() {
        var signals = SessionSignals(sessionID: "test-1")
        signals.firstUserIntent = "帮我重构认证模块"
        signals.branch = "feat/auth"
        signals.toolsUsed = ["Edit", "Bash"]
        signals.turnCount = 15

        let input = LLMPrompts.titleInput(from: signals)
        XCTAssertTrue(input.contains("帮我重构认证模块"))
        XCTAssertTrue(input.contains("feat/auth"))
        XCTAssertTrue(input.contains("15"))
    }

    func testPromptInputIncludesRawTurns() {
        var signals = SessionSignals(sessionID: "test-1")
        signals.firstUserIntent = "test"

        let input = LLMPrompts.titleInput(from: signals, rawTurns: ["用户: 帮我修bug", "助手: 好的"])
        XCTAssertTrue(input.contains("帮我修bug"))
        XCTAssertTrue(input.contains("好的"))
    }

    func testRawTurnsNotRetruncatedByPromptBuilder() {
        // Regression: rawTurns was being re-truncated to prefix(3) inside titleInput,
        // which defeated the upstream sampling that provided 8 turns for long sessions.
        var signals = SessionSignals(sessionID: "s1")
        signals.firstUserIntent = "test"
        let turns = (1...8).map { "用户: 第\($0)轮对话内容" }

        let input = LLMPrompts.titleInput(from: signals, rawTurns: turns)
        // All 8 turns must appear in the output, not just 3
        for turn in turns {
            XCTAssertTrue(input.contains(turn), "Missing turn: \(turn)")
        }
        XCTAssertTrue(input.contains("8 条"), "Should show turn count")
    }

    func testMilestoneHistoryPreservesVersionEntries() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = [
            "读交接文档",
            "brainstorming v0.2.0 方向",
            "普通对话1", "普通对话2", "普通对话3",
            "普通对话4", "普通对话5", "普通对话6",
            "封版 v0.2.0 准备 v0.2.5",
            "v0.2.5 LLM 增强开发",
            "最后一条对话"
        ]

        let input = LLMPrompts.titleInput(from: signals)
        // Version-related entries must appear in milestones section
        XCTAssertTrue(input.contains("v0.2.0"), "Must preserve v0.2.0 milestone")
        XCTAssertTrue(input.contains("v0.2.5"), "Must preserve v0.2.5 milestone")
        XCTAssertTrue(input.contains("关键里程碑"), "Must have milestone section")
    }

    func testPromptInputBoundsLength() {
        var signals = SessionSignals(sessionID: "s1")
        signals.firstUserIntent = String(repeating: "长文本", count: 500)
        signals.historyDisplayTexts = [String(repeating: "历史", count: 500)]

        let input = LLMPrompts.titleInput(from: signals)
        XCTAssertTrue(input.count < 5000)
    }

    func testEnhancerReturnsNilWhenUnconfigured() async {
        var signals = SessionSignals(sessionID: "s1")
        signals.firstUserIntent = "test"
        signals.turnCount = 5
        signals.toolsUsed = ["Edit"]

        let enhancer = LLMEnhancer(config: LLMConfig())
        let result = await enhancer.enhance(signals: signals, basedOnLastActiveAt: Date())
        XCTAssertNil(result)
    }

    func testSystemPromptsAreNonEmpty() {
        XCTAssertFalse(LLMPrompts.titleSystemPrompt.isEmpty)
        XCTAssertFalse(LLMPrompts.progressSystemPrompt.isEmpty)
        XCTAssertFalse(LLMPrompts.summarySystemPrompt.isEmpty)
    }

    func testPromptInputIncludesTaskInfo() {
        var signals = SessionSignals(sessionID: "s1")
        signals.taskSubject = "Refactor auth middleware"
        signals.taskStatus = "in_progress"

        let input = LLMPrompts.titleInput(from: signals)
        XCTAssertTrue(input.contains("Refactor auth middleware"))
        XCTAssertTrue(input.contains("in_progress"))
    }
}
