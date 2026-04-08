import Foundation
import Observation

/// Persists LLM understanding snapshots. Completely independent from TitleStore.
@Observable
public final class UnderstandingStore {
    private var snapshots: [String: LLMUnderstandingSnapshot] = [:]
    private let filePath: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("understanding.json")
        load()
    }

    public func snapshot(for sessionID: String) -> LLMUnderstandingSnapshot? {
        snapshots[sessionID]
    }

    public func hasEnhancement(for sessionID: String) -> Bool {
        snapshots[sessionID] != nil
    }

    /// Returns true if the snapshot exists but is older than the session's last activity.
    public func isStale(for sessionID: String, lastActiveAt: Date) -> Bool {
        guard let snapshot = snapshots[sessionID] else { return false }
        return lastActiveAt > snapshot.basedOnLastActiveAt
    }

    public func setSnapshot(_ snapshot: LLMUnderstandingSnapshot) {
        // Always overwrite — even if text is identical, metadata (generatedAt,
        // basedOnLastActiveAt) may have advanced. Skipping would leave the
        // snapshot permanently stale after a same-content refresh.
        snapshots[snapshot.sessionID] = snapshot
        save()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let stored = try? JSONDecoder().decode([String: LLMUnderstandingSnapshot].self, from: data)
        else { return }
        snapshots = stored
    }

    private func save() {
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
