import Foundation

typealias ProviderID = String

struct ProviderCapabilities: OptionSet, Sendable {
    let rawValue: Int
    static let resume        = ProviderCapabilities(rawValue: 1 << 0)
    static let contextUsage  = ProviderCapabilities(rawValue: 1 << 1)
    static let errorTracking = ProviderCapabilities(rawValue: 1 << 2)
    static let branchInfo    = ProviderCapabilities(rawValue: 1 << 3)
}

struct ModelInfo: Sendable, Equatable {
    let modelName: String
    let contextLimit: Int

    static func resolve(modelName: String?) -> ModelInfo {
        guard let name = modelName else {
            return ModelInfo(modelName: "unknown", contextLimit: 200_000)
        }
        let limit: Int
        if name.hasPrefix("claude-opus-4") {
            limit = 1_000_000
        } else if name.hasPrefix("claude-sonnet-4") {
            limit = 200_000
        } else if name.hasPrefix("claude-haiku-4") {
            limit = 200_000
        } else {
            limit = 200_000
        }
        return ModelInfo(modelName: name, contextLimit: limit)
    }
}
