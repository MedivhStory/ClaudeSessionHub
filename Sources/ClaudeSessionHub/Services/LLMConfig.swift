import Foundation

/// Configuration for optional LLM enhancement.
/// When unconfigured (empty endpoint/key), the app uses rule-based strategies only.
public struct LLMConfig: Codable, Sendable, Equatable {
    public var endpoint: String = ""
    public var apiKey: String = ""
    public var modelName: String = ""

    /// True only when endpoint, apiKey, AND modelName are all non-empty.
    public var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init() {}
}
