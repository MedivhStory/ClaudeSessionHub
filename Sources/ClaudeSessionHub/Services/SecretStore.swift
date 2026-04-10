import Foundation
import Security

/// Abstraction for secret storage. Keychain in production, in-memory for tests.
public protocol SecretStore: Sendable {
    func save(key: String, value: String) throws
    func load(key: String) -> String?
    func delete(key: String)
}

/// Real macOS Keychain implementation.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "com.claudehub.llm") {
        self.service = service
    }

    public func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        // Delete existing first
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory implementation for tests and UI-test mode. Never touches real Keychain.
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
