import Foundation

public typealias ProviderID = String

public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let resume        = ProviderCapabilities(rawValue: 1 << 0)
    public static let contextUsage  = ProviderCapabilities(rawValue: 1 << 1)
    public static let errorTracking = ProviderCapabilities(rawValue: 1 << 2)
    public static let branchInfo    = ProviderCapabilities(rawValue: 1 << 3)
}

public struct ModelInfo: Sendable, Equatable {
    public let modelName: String
    public let contextLimit: Int

    public init(modelName: String, contextLimit: Int) {
        self.modelName = modelName
        self.contextLimit = contextLimit
    }

    public static func resolve(modelName: String?) -> ModelInfo {
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
