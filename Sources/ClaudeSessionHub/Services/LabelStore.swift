import Foundation
import Observation

/// Not Sendable — accessed only from @MainActor context via SessionStore.
/// Swift 6 migration: annotate with @MainActor or convert to actor.
@Observable
public final class LabelStore {
    private var labels: [String: String] = [:]
    private let filePath: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("labels.json")
        load()
    }

    public func label(for ref: SessionRef) -> String? {
        labels["\(ref.providerID):\(ref.sessionID)"]
    }

    public func setLabel(for ref: SessionRef, label: String?) {
        let key = "\(ref.providerID):\(ref.sessionID)"
        if let label {
            labels[key] = label
        } else {
            labels.removeValue(forKey: key)
        }
        save()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        labels = dict
    }

    private func save() {
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: labels, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
