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
}
