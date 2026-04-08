import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMClientTests: XCTestCase {

    func testBuildRequestFormat() throws {
        var config = LLMConfig()
        config.endpoint = "https://api.example.com/v1/chat/completions"
        config.apiKey = "sk-test"
        config.modelName = "gpt-4o"
        let client = LLMClient(config: config)

        let request = try client.buildRequest(
            systemPrompt: "You are a title generator.",
            userMessage: "Session about auth refactoring",
            maxTokens: 100
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        XCTAssertEqual(body["model"] as? String, "gpt-4o")
    }

    func testParseResponseExtractsContent() throws {
        let json: [String: Any] = [
            "choices": [
                ["message": ["content": "重构认证中间件"]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let content = try LLMClient.parseResponseContent(from: data)
        XCTAssertEqual(content, "重构认证中间件")
    }

    func testParseErrorResponse() {
        let json: [String: Any] = [
            "error": ["message": "Invalid API key"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try LLMClient.parseResponseContent(from: data)) { error in
            XCTAssertTrue("\(error)".contains("Invalid API key"))
        }
    }

    func testAuthHeaderIncludesApiKey() throws {
        var config = LLMConfig()
        config.endpoint = "https://api.example.com/v1/chat/completions"
        config.apiKey = "sk-test-key"
        config.modelName = "gpt-4o"
        let client = LLMClient(config: config)

        let request = try client.buildRequest(
            systemPrompt: "test", userMessage: "test", maxTokens: 50
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
    }

    func testBuildRequestThrowsWhenNotConfigured() {
        let config = LLMConfig()
        let client = LLMClient(config: config)

        XCTAssertThrowsError(try client.buildRequest(
            systemPrompt: "test", userMessage: "test", maxTokens: 50
        ))
    }

    func testBaseURLAutoAppendsChatCompletions() throws {
        var config = LLMConfig()
        config.endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        config.apiKey = "sk-test"
        config.modelName = "qwen-plus"
        let client = LLMClient(config: config)

        let request = try client.buildRequest(
            systemPrompt: "test", userMessage: "test", maxTokens: 50
        )
        XCTAssertEqual(request.url?.absoluteString,
                       "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    func testOllamaNoAuthHeader() throws {
        var config = LLMConfig.preset(.ollama)
        config.modelName = "llama3"
        let client = LLMClient(config: config)

        let request = try client.buildRequest(
            systemPrompt: "test", userMessage: "test", maxTokens: 50
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
