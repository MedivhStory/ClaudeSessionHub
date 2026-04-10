import Foundation

/// Abstraction for secret storage.
public protocol SecretStore: Sendable {
    func save(key: String, value: String) throws
    func load(key: String) -> String?
    func delete(key: String)
}

/// File-based secret storage with restricted permissions (0600).
/// Stores secrets in a dedicated file outside settings.json.
/// Avoids macOS Keychain issues with unsigned apps (permission dialogs, frozen UI).
public struct FileSecretStore: SecretStore {
    private let directory: String

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.directory = directory
    }

    private func filePath(for key: String) -> String {
        (directory as NSString).appendingPathComponent(".\(key).secret")
    }

    public func save(key: String, value: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = filePath(for: key)
        let data = Data(value.utf8)
        try data.write(to: URL(fileURLWithPath: path))
        // Set file permissions to owner-only read/write (0600)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    public func load(key: String) -> String? {
        let path = filePath(for: key)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func delete(key: String) {
        try? FileManager.default.removeItem(atPath: filePath(for: key))
    }
}

/// In-memory implementation for tests and UI-test mode.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var store: [String: String] = [:]

    public init() {}

    public func save(key: String, value: String) throws {
        store[key] = value
    }

    public func load(key: String) -> String? {
        store[key]
    }

    public func delete(key: String) {
        store.removeValue(forKey: key)
    }
}
