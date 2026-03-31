import Foundation
import Observation

@Observable
public final class ArchiveStore {
    private var archivedKeys: Set<String> = []
    private let filePath: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("archived.json")
        load()
    }

    public func isArchived(_ ref: SessionRef) -> Bool {
        archivedKeys.contains(key(for: ref))
    }

    public func archive(_ ref: SessionRef) {
        archivedKeys.insert(key(for: ref))
        save()
    }

    public func unarchive(_ ref: SessionRef) {
        archivedKeys.remove(key(for: ref))
        save()
    }

    private func key(for ref: SessionRef) -> String {
        "\(ref.providerID):\(ref.sessionID)"
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return }
        archivedKeys = Set(array)
    }

    private func save() {
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let array = Array(archivedKeys).sorted()
        guard let data = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
