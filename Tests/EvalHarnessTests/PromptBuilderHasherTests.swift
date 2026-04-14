import XCTest
@testable import EvalHarnessCore
import ClaudeSessionHubLib  // for LLMPrompts

final class PromptBuilderHasherTests: XCTestCase {
    func test_currentHash_startsWithSha256Prefix() throws {
        let hash = PromptBuilderHasher.currentHash()
        XCTAssertTrue(hash.hasPrefix("sha256:"))
    }

    func test_currentHash_stableOnRepeatedCalls() throws {
        let a = PromptBuilderHasher.currentHash()
        let b = PromptBuilderHasher.currentHash()
        XCTAssertEqual(a, b)
    }

    func test_canonicalBlob_containsAllFourSections() throws {
        let blob = PromptBuilderHasher.canonicalBlob()
        XCTAssertTrue(blob.contains("titleSystemPrompt="))
        XCTAssertTrue(blob.contains("progressSystemPrompt="))
        XCTAssertTrue(blob.contains("summarySystemPrompt="))
        XCTAssertTrue(blob.contains("titleInputSource="))
    }

    func test_canonicalBlob_containsGeneratedSource() throws {
        let blob = PromptBuilderHasher.canonicalBlob()
        // The generated source should contain "MilestoneSampler" since titleInput calls it
        XCTAssertTrue(blob.contains("MilestoneSampler"))
    }
}
