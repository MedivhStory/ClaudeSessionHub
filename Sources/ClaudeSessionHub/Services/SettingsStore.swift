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
    private var apiKeyLoaded = false
    private var legacyApiKey: String?  // from plaintext JSON, pending migration

    public init(directory: String = NSHomeDirectory() + "/.claude-hub",
                secretStore: SecretStore = FileSecretStore()) {
        self.filePath = (directory as NSString).appendingPathComponent("settings.json")
        self.secretStore = secretStore
        load()
    }

    /// Lazily load API key from secret storage. Called only when AI features are actually used.
    /// This avoids triggering file/permission access at app startup.
    public func ensureApiKeyLoaded() {
        guard !apiKeyLoaded else { return }
        apiKeyLoaded = true

        // Try secret store first
        if let storedKey = secretStore.load(key: "apiKey") {
            llmConfig.apiKey = storedKey
        }
        // Migration: legacy plaintext key from JSON → secret store
        else if let legacyKey = legacyApiKey, !legacyKey.isEmpty {
            llmConfig.apiKey = legacyKey
            try? secretStore.save(key: "apiKey", value: legacyKey)
            save()  // re-save to remove plaintext from JSON
        }
        legacyApiKey = nil
    }

    public func setSelectedTerminal(_ value: String) {
        selectedTerminal = value
        save()
    }

    public func setClaudeDataDirectory(_ value: String) {
        claudeDataDirectory = Self.normalizePath(value)
        save()
    }

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
        if !config.apiKey.isEmpty {
            try? secretStore.save(key: "apiKey", value: config.apiKey)
        } else {
            secretStore.delete(key: "apiKey")
        }
        apiKeyLoaded = true
        llmConfig = config
        save()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let t = dict["selectedTerminal"] as? String { selectedTerminal = t }
        if let d = dict["claudeDataDirectory"] as? String { claudeDataDirectory = Self.normalizePath(d) }
        if let s = dict["scanIntervalSeconds"] as? Int { scanIntervalSeconds = s }

        if let raw = dict["llmConfig"] as? [String: Any] {
            // Extract legacy plaintext apiKey — will be migrated lazily
            legacyApiKey = raw["apiKey"] as? String

            // Decode config — init(from:) may pick up legacy apiKey from raw JSON,
            // but we clear it here. apiKey is loaded lazily from SecretStore.
            if let jsonData = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode(LLMConfig.self, from: jsonData) {
                llmConfig = decoded
                llmConfig.apiKey = ""  // Clear — will be loaded from SecretStore on demand
            }
            // Do NOT touch secret store here — deferred to ensureApiKeyLoaded()
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
