import Foundation
import Observation

@Observable
public final class SettingsStore {
    public var selectedTerminal: String = "Ghostty"
    public var claudeDataDirectory: String = NSHomeDirectory() + "/.claude"
    public var scanIntervalSeconds: Int = 60
    public var llmConfig: LLMConfig = LLMConfig()

    private let filePath: String
    private let secretStore: SecretStore

    public init(directory: String = NSHomeDirectory() + "/.claude-hub",
                secretStore: SecretStore = KeychainSecretStore()) {
        self.filePath = (directory as NSString).appendingPathComponent("settings.json")
        self.secretStore = secretStore
        load()
    }

    public func setSelectedTerminal(_ value: String) {
        selectedTerminal = value
        save()
    }

    public func setClaudeDataDirectory(_ value: String) {
        claudeDataDirectory = Self.normalizePath(value)
        save()
    }

    /// Trim whitespace and expand ~ to home directory.
    static func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~/") {
            return NSHomeDirectory() + String(trimmed.dropFirst(1))
        }
        if trimmed == "~" {
            return NSHomeDirectory()
        }
        return trimmed
    }

    public func setScanIntervalSeconds(_ value: Int) {
        scanIntervalSeconds = value
        save()
    }

    public func setLLMConfig(_ config: LLMConfig) {
        // Save apiKey to SecretStore, not JSON
        if !config.apiKey.isEmpty {
            try? secretStore.save(key: "apiKey", value: config.apiKey)
        } else {
            secretStore.delete(key: "apiKey")
        }
        llmConfig = config
        save()  // This will encode LLMConfig WITHOUT apiKey
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let t = dict["selectedTerminal"] as? String { selectedTerminal = t }
        if let d = dict["claudeDataDirectory"] as? String { claudeDataDirectory = Self.normalizePath(d) }
        if let s = dict["scanIntervalSeconds"] as? Int { scanIntervalSeconds = s }

        // LLM config: decode from JSON, then handle apiKey separately
        if let raw = dict["llmConfig"] as? [String: Any] {
            // Step 1: Extract legacy plaintext apiKey from raw JSON BEFORE decoding
            let legacyApiKey = raw["apiKey"] as? String

            // Step 2: Decode the rest of LLMConfig (apiKey will be empty since encode skips it)
            if let jsonData = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode(LLMConfig.self, from: jsonData) {
                llmConfig = decoded
            }

            // Step 3: Load apiKey from SecretStore
            if let keychainKey = secretStore.load(key: "apiKey") {
                llmConfig.apiKey = keychainKey
            }
            // Step 4: Migration — if SecretStore empty but legacy JSON has key, migrate
            else if let legacyKey = legacyApiKey, !legacyKey.isEmpty {
                llmConfig.apiKey = legacyKey
                try? secretStore.save(key: "apiKey", value: legacyKey)
                // Re-save to remove plaintext key from JSON
                save()
            }
        }
    }

    public func save() {
        var dict: [String: Any] = [
            "selectedTerminal": selectedTerminal,
            "claudeDataDirectory": claudeDataDirectory,
            "scanIntervalSeconds": scanIntervalSeconds
        ]
        if let encoded = try? JSONEncoder().encode(llmConfig),
           let llmDict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            dict["llmConfig"] = llmDict
        }
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
