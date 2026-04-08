import Foundation

/// Supported LLM provider presets.
public enum LLMProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case dashscope = "阿里云百炼"
    case dashscopeIntl = "阿里云百炼(国际)"
    case dashscopeUS = "阿里云百炼(美国)"
    case deepseek = "DeepSeek"
    case moonshot = "Moonshot (月之暗面)"
    case ollama = "Ollama (本地)"
    case custom = "自定义"

    public var id: String { rawValue }

    /// Base URL for the provider's OpenAI-compatible API.
    /// For custom, returns empty — user fills in manually.
    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .dashscope: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .dashscopeIntl: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .dashscopeUS: return "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .custom: return ""
        }
    }

    /// Suggested model names for this provider.
    public var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "o3-mini"]
        case .dashscope, .dashscopeIntl, .dashscopeUS:
            return ["qwen-plus", "qwen-turbo", "qwen-max", "qwen-long", "qwen3-235b-a22b"]
        case .deepseek: return ["deepseek-chat", "deepseek-reasoner"]
        case .moonshot: return ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"]
        case .ollama: return ["llama3", "mistral", "codellama", "qwen2"]
        case .custom: return []
        }
    }

    /// Whether this provider requires an API key (Ollama typically doesn't).
    public var requiresApiKey: Bool {
        self != .ollama
    }
}

/// Configuration for optional LLM enhancement.
/// When unconfigured (empty endpoint/key/model), the app uses rule-based strategies only.
public struct LLMConfig: Codable, Sendable, Equatable {
    public var provider: LLMProvider = .custom
    public var endpoint: String = ""
    public var apiKey: String = ""
    public var modelName: String = ""

    /// The full chat completions endpoint URL.
    /// Automatically appends /chat/completions if the endpoint is a base URL.
    public var resolvedEndpoint: String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // If already ends with /chat/completions, use as-is
        if trimmed.hasSuffix("/chat/completions") { return trimmed }
        // Otherwise append it
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return base + "/chat/completions"
    }

    /// True when the config has enough info to make API calls.
    public var isConfigured: Bool {
        !resolvedEndpoint.isEmpty &&
        (!provider.requiresApiKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init() {}

    /// Create a config from a provider preset.
    public static func preset(_ provider: LLMProvider) -> LLMConfig {
        var config = LLMConfig()
        config.provider = provider
        config.endpoint = provider.defaultBaseURL
        config.modelName = provider.suggestedModels.first ?? ""
        return config
    }
}
