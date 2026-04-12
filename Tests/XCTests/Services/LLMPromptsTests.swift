import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMPromptsTests: XCTestCase {
    func test_titleSystemPrompt_currentlyContainsHardVersionRequirement_willBeRemoved() {
        // This test documents the pre-refactor state.
        // After Task 5.2, this test will FAIL — that's intentional (TDD red step).
        // Then we replace it with its inverse in Task 5.2.
        XCTAssertTrue(LLMPrompts.titleSystemPrompt.contains("必须包含该版本号"))
    }
}
