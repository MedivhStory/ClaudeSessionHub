import Foundation
import Observation

@Observable
public final class TitleStore {
    private var titles: [String: TitleHistory] = [:]
    private var progressMap: [String: String] = [:]
    private var userNotes: [String: String] = [:]
    private let filePath: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("titles.json")
        load()
    }

    // MARK: - Title

    public func currentTitle(for sessionID: String) -> GeneratedTitle? {
        titles[sessionID]?.current
    }

    public func titleHistory(for sessionID: String) -> [GeneratedTitle] {
        titles[sessionID]?.entries ?? []
    }

    public func setTitle(for sessionID: String, title: GeneratedTitle) {
        // Deduplicate: only append if title text actually changed
        if let current = titles[sessionID]?.current,
           current.text == title.text && current.source == title.source {
            return // same title, skip
        }
        if titles[sessionID] == nil {
            titles[sessionID] = TitleHistory(sessionID: sessionID)
        }
        titles[sessionID]!.append(title)
        save()
    }

    // MARK: - Last Progress

    public func lastProgress(for sessionID: String) -> String? {
        progressMap[sessionID]
    }

    public func setLastProgress(for sessionID: String, progress: String?) {
        // Skip if unchanged
        if progressMap[sessionID] == progress { return }
        if let progress {
            progressMap[sessionID] = progress
        } else {
            progressMap.removeValue(forKey: sessionID)
        }
        save()
    }

    // MARK: - User Note

    public func userNote(for sessionID: String) -> String? {
        userNotes[sessionID]
    }

    public func setUserNote(for sessionID: String, note: String?) {
        if let note, !note.isEmpty {
            userNotes[sessionID] = note
        } else {
            userNotes.removeValue(forKey: sessionID)
        }
        save()
    }

    // MARK: - Persistence

    private struct StorageFormat: Codable {
        var titles: [String: TitleHistory]
        var progress: [String: String]
        var userNotes: [String: String]
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let stored = try? JSONDecoder().decode(StorageFormat.self, from: data) else { return }
        titles = stored.titles
        progressMap = stored.progress
        userNotes = stored.userNotes
    }

    private func save() {
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stored = StorageFormat(titles: titles, progress: progressMap, userNotes: userNotes)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
