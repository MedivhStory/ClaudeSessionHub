import Foundation
import Observation

@Observable
public final class SettingsStore {
    public var selectedTerminal: String = "Ghostty"
    public var claudeDataDirectory: String = NSHomeDirectory() + "/.claude"
    public var scanIntervalSeconds: Int = 60
    public var llmConfig: LLMConfig = LLMConfig()

    private let filePath: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("settings.json")
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
        llmConfig = config
        save()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let t = dict["selectedTerminal"] as? String { selectedTerminal = t }
        if let d = dict["claudeDataDirectory"] as? String { claudeDataDirectory = Self.normalizePath(d) }
        if let s = dict["scanIntervalSeconds"] as? Int { scanIntervalSeconds = s }
        if let raw = dict["llmConfig"] as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: raw),
           let decoded = try? JSONDecoder().decode(LLMConfig.self, from: jsonData) {
            llmConfig = decoded
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
