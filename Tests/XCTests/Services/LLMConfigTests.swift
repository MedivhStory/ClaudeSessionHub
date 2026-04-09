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
        XCTAssertEqual(config.provider, .custom)
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
        XCTAssertFalse(config.isConfigured, "Must require modelName to be configured")
    }

    // MARK: - Provider Presets

    func testPresetFillsEndpointAndModel() {
        let config = LLMConfig.preset(.openai)
        XCTAssertEqual(config.provider, .openai)
        XCTAssertEqual(config.endpoint, "https://api.openai.com/v1")
        XCTAssertEqual(config.modelName, "gpt-4o")
    }

    func testDashscopePreset() {
        let config = LLMConfig.preset(.dashscope)
        XCTAssertEqual(config.endpoint, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(config.modelName, "qwen-plus")
    }

    func testDeepSeekPreset() {
        let config = LLMConfig.preset(.deepseek)
        XCTAssertEqual(config.endpoint, "https://api.deepseek.com/v1")
        XCTAssertEqual(config.modelName, "deepseek-chat")
    }

    func testOllamaPreset() {
        let config = LLMConfig.preset(.ollama)
        XCTAssertEqual(config.endpoint, "http://localhost:11434/v1")
        XCTAssertFalse(config.provider.requiresApiKey)
    }

    // MARK: - Resolved Endpoint

    func testResolvedEndpointAppendsPath() {
        var config = LLMConfig()
        config.endpoint = "https://api.openai.com/v1"
        XCTAssertEqual(config.resolvedEndpoint, "https://api.openai.com/v1/chat/completions")
    }

    func testResolvedEndpointNoDoubleAppend() {
        var config = LLMConfig()
        config.endpoint = "https://api.openai.com/v1/chat/completions"
        XCTAssertEqual(config.resolvedEndpoint, "https://api.openai.com/v1/chat/completions")
    }

    func testResolvedEndpointHandlesTrailingSlash() {
        var config = LLMConfig()
        config.endpoint = "https://api.openai.com/v1/"
        XCTAssertEqual(config.resolvedEndpoint, "https://api.openai.com/v1/chat/completions")
    }

    func testResolvedEndpointDashscope() {
        var config = LLMConfig()
        config.endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        XCTAssertEqual(config.resolvedEndpoint,
                       "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    // MARK: - Ollama no API key

    func testOllamaConfiguredWithoutApiKey() {
        var config = LLMConfig.preset(.ollama)
        config.modelName = "llama3"
        // No API key needed for Ollama
        XCTAssertTrue(config.isConfigured, "Ollama should be configured without API key")
    }

    // MARK: - Backward Compatibility

    func testDecodesV025ConfigWithoutProviderField() throws {
        // v0.2.5 configs have no "provider" key — must default to .custom
        let json = """
        {"endpoint":"https://api.openai.com/v1","apiKey":"sk-test","modelName":"gpt-4o"}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(LLMConfig.self, from: json)
        XCTAssertEqual(config.provider, .custom)
        XCTAssertEqual(config.endpoint, "https://api.openai.com/v1")
        XCTAssertEqual(config.apiKey, "sk-test")
        XCTAssertEqual(config.modelName, "gpt-4o")
    }

    // MARK: - Persistence

    func testConfigPersistsThroughSettingsStore() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        var config = LLMConfig()
        config.provider = .dashscope
        config.endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        config.apiKey = "test-key"
        config.modelName = "qwen-plus"
        store.setLLMConfig(config)

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.llmConfig.provider, .dashscope)
        XCTAssertEqual(store2.llmConfig.endpoint, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(store2.llmConfig.apiKey, "test-key")
        XCTAssertEqual(store2.llmConfig.modelName, "qwen-plus")
    }

    // MARK: - Provider properties

    func testAllProvidersHaveBaseURL() {
        for provider in LLMProvider.allCases where provider != .custom {
            XCTAssertFalse(provider.defaultBaseURL.isEmpty, "\(provider) must have a base URL")
        }
    }

    func testAllNonCustomProvidersHaveSuggestedModels() {
        for provider in LLMProvider.allCases where provider != .custom {
            XCTAssertFalse(provider.suggestedModels.isEmpty, "\(provider) must have suggested models")
        }
    }
}
