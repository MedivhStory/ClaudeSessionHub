import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMConfigTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "llmconfig-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDefaultConfigIsDisabled() {
        let config = LLMConfig()
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.endpoint, "")
        XCTAssertEqual(config.apiKey, "")
        XCTAssertEqual(config.modelName, "")
    }

    func testConfiguredWhenEndpointAndKeyPresent() {
        var config = LLMConfig()
        config.endpoint = "https://api.openai.com/v1/chat/completions"
        config.apiKey = "sk-test-123"
        config.modelName = "gpt-4o"
        XCTAssertTrue(config.isConfigured)
    }

    func testNotConfiguredWhenModelNameMissing() {
        var config = LLMConfig()
        config.endpoint = "https://api.openai.com/v1/chat/completions"
        config.apiKey = "sk-test-123"
        // modelName is empty
        XCTAssertFalse(config.isConfigured, "Must require modelName to be configured")
    }

    func testConfigPersistsThroughSettingsStore() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        var config = LLMConfig()
        config.endpoint = "https://api.example.com/v1/chat/completions"
        config.apiKey = "test-key"
        config.modelName = "claude-sonnet-4-20250514"
        store.setLLMConfig(config)

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.llmConfig.endpoint, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(store2.llmConfig.apiKey, "test-key")
        XCTAssertEqual(store2.llmConfig.modelName, "claude-sonnet-4-20250514")
    }
}
