import Foundation

public final class SettingsStore {
    public var selectedTerminal: String = "Ghostty"
    public var claudeDataDirectory: String = NSHomeDirectory() + "/.claude"
    public var scanIntervalSeconds: Int = 60

    private let filePath: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("settings.json")
        load()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let t = dict["selectedTerminal"] as? String { selectedTerminal = t }
        if let d = dict["claudeDataDirectory"] as? String { claudeDataDirectory = d }
        if let s = dict["scanIntervalSeconds"] as? Int { scanIntervalSeconds = s }
    }

    public func save() {
        let dict: [String: Any] = [
            "selectedTerminal": selectedTerminal,
            "claudeDataDirectory": claudeDataDirectory,
            "scanIntervalSeconds": scanIntervalSeconds
        ]
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
