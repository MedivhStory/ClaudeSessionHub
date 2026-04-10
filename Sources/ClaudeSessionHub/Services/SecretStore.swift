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
        // Create directory with 0700 (owner-only access)
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let path = filePath(for: key)
        let data = Data(value.utf8)
        // Atomic creation with 0600 permissions — no race window
        fm.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
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

/// In-memory implementation for tests and UI-test mode. Thread-safe via NSLock.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store[key] = value
    }

    public func load(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    public func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}
