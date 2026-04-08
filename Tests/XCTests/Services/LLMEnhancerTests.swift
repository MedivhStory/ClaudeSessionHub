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
