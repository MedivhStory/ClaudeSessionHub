import Foundation

/// Reads enrichment data sources (history.jsonl, tasks/) and produces structured signals.
/// Does NOT read session JSONL — that stays in ClaudeProvider.
public struct SignalExtractor: Sendable {
    private let baseDirectoryProvider: @Sendable () -> String
    private var baseDirectory: String { baseDirectoryProvider() }

    public init(baseDirectory: String = NSHomeDirectory() + "/.claude") {
        let dir = baseDirectory
        self.baseDirectoryProvider = { dir }
    }

    /// Initialize with a dynamic directory provider (for hot-switch support).
    public init(baseDirectoryProvider: @escaping @Sendable () -> String) {
        self.baseDirectoryProvider = baseDirectoryProvider
    }

    // MARK: - history.jsonl

    /// Returns all `display` texts from history.jsonl for a given sessionId, in chronological order.
    public func historyDisplayTexts(for sessionID: String) -> [String] {
        let path = baseDirectory + "/history.jsonl"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return [] }

        var results: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard json["sessionId"] as? String == sessionID else { continue }
            guard let display = json["display"] as? String else { continue }
            let clean = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                results.append(clean)
            }
        }
        return results
    }

    // MARK: - tasks/

    public struct TaskSignal: Sendable, Equatable {
        public let id: String
        public let subject: String
        public let description: String?
        public let status: String
    }

    /// Returns all tasks for a given sessionId from ~/.claude/tasks/{sessionId}/*.json
    public func taskSignals(for sessionID: String) -> [TaskSignal] {
        let tasksDir = baseDirectory + "/tasks/" + sessionID
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: tasksDir) else { return [] }

        var results: [TaskSignal] = []
        for file in files where file.hasSuffix(".json") {
            let path = tasksDir + "/" + file
            guard let data = fm.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String,
                  let subject = json["subject"] as? String,
                  let status = json["status"] as? String else { continue }
            results.append(TaskSignal(
                id: id,
                subject: subject,
                description: json["description"] as? String,
                status: status
            ))
        }
        return results.sorted { $0.id < $1.id }
    }

    // MARK: - Aggregate

    /// Build complete SessionSignals by combining all enrichment sources.
    /// `jsonlSignals` is a partially-filled SessionSignals from ClaudeProvider (JSONL fields only).
    public func enrich(_ jsonlSignals: SessionSignals) -> SessionSignals {
        var signals = jsonlSignals

        // history.jsonl enrichment
        let allHistory = historyDisplayTexts(for: signals.sessionID)
        signals.historyDisplayTexts = allHistory
        signals.historyCount = allHistory.count

        // tasks/ enrichment
        let tasks = taskSignals(for: signals.sessionID)
        let preferred = tasks.first { $0.status == "in_progress" } ?? tasks.last
        signals.taskSubject = preferred?.subject
        signals.taskDescription = preferred?.description
        signals.taskStatus = preferred?.status

        return signals
    }
}
