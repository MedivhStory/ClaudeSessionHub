import Foundation

/// OpenAI-compatible chat completions client. Pure HTTP, no external deps.
public struct LLMClient: Sendable {
    private let config: LLMConfig

    public init(config: LLMConfig) {
        self.config = config
    }

    public enum LLMError: Error, LocalizedError {
        case notConfigured
        case invalidEndpoint
        case apiError(String)
        case networkError(Error)
        case parseError(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "LLM 未配置"
            case .invalidEndpoint: return "无效的 API 地址"
            case .apiError(let msg): return "API 错误: \(msg)"
            case .networkError(let err): return "网络错误: \(err.localizedDescription)"
            case .parseError(let msg): return "解析错误: \(msg)"
            }
        }
    }

    /// Build a URLRequest for chat completions.
    public func buildRequest(systemPrompt: String, userMessage: String, maxTokens: Int) throws -> URLRequest {
        guard config.isConfigured else { throw LLMError.notConfigured }
        guard let url = URL(string: config.endpoint) else { throw LLMError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Execute a chat completion and return the assistant's response text.
    public func complete(systemPrompt: String, userMessage: String, maxTokens: Int = 200) async throws -> String {
        let request = try buildRequest(systemPrompt: systemPrompt, userMessage: userMessage, maxTokens: maxTokens)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorContent = try? Self.parseErrorMessage(from: data) {
                throw LLMError.apiError("HTTP \(httpResponse.statusCode): \(errorContent)")
            }
            throw LLMError.apiError("HTTP \(httpResponse.statusCode)")
        }

        return try Self.parseResponseContent(from: data)
    }

    /// Parse assistant content from OpenAI-compatible response JSON.
    public static func parseResponseContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.parseError("Invalid JSON")
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw LLMError.apiError(message)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError("Missing choices[0].message.content")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseErrorMessage(from data: Data) throws -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }

    /// Test connection by sending a minimal request.
    public func testConnection() async throws -> String {
        let response = try await complete(
            systemPrompt: "Reply with exactly: OK",
            userMessage: "Test",
            maxTokens: 10
        )
        return response
    }
}
