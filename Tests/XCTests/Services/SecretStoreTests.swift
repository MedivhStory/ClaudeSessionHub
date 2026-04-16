import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class SecretStoreTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "secretstore-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - InMemorySecretStore

    func testInMemorySaveAndLoad() throws {
        let store = InMemorySecretStore()
        try store.save(key: "apiKey", value: "sk-test-123")
        XCTAssertEqual(store.load(key: "apiKey"), "sk-test-123")
    }

    func testInMemoryDelete() throws {
        let store = InMemorySecretStore()
        try store.save(key: "apiKey", value: "sk-test")
        store.delete(key: "apiKey")
        XCTAssertNil(store.load(key: "apiKey"))
    }

    func testInMemoryLoadMissing() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.load(key: "nonexistent"))
    }

    // MARK: - Migration from plaintext

    func testMigrationFromPlaintextJSON() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let secretStore = InMemorySecretStore()

        // Write old-style settings.json WITH plaintext apiKey
        let oldConfig: [String: Any] = [
            "selectedTerminal": "Ghostty",
            "claudeDataDirectory": NSHomeDirectory() + "/.claude",
            "scanIntervalSeconds": 60,
            "llmConfig": [
                "provider": "openai",
                "endpoint": "https://api.openai.com/v1",
                "apiKey": "sk-plaintext-secret",
                "modelName": "gpt-4o"
            ]
        ]
        let path = (dir as NSString).appendingPathComponent("settings.json")
        let data = try! JSONSerialization.data(withJSONObject: oldConfig, options: .prettyPrinted)
        try! data.write(to: URL(fileURLWithPath: path))

        // Load — migration now happens eagerly at init
        let store = SettingsStore(directory: dir, secretStore: secretStore)

        // API key should now be in SecretStore
        XCTAssertEqual(secretStore.load(key: "apiKey"), "sk-plaintext-secret")
        // And accessible via llmConfig
        XCTAssertEqual(store.llmConfig.apiKey, "sk-plaintext-secret")

        // Verify plaintext key was removed from JSON
        let reloadedData = FileManager.default.contents(atPath: path)!
        let reloadedDict = try! JSONSerialization.jsonObject(with: reloadedData) as! [String: Any]
        let reloadedLLM = reloadedDict["llmConfig"] as! [String: Any]
        XCTAssertNil(reloadedLLM["apiKey"], "Plaintext apiKey must be removed from JSON after migration")
    }

    func testNoMigrationWhenSecretStoreAlreadyHasKey() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let secretStore = InMemorySecretStore()
        try! secretStore.save(key: "apiKey", value: "sk-already-in-keychain")

        // Write old-style JSON with different key
        let oldConfig: [String: Any] = [
            "llmConfig": [
                "provider": "openai",
                "endpoint": "https://api.openai.com/v1",
                "apiKey": "sk-old-plaintext",
                "modelName": "gpt-4o"
            ]
        ]
        let path = (dir as NSString).appendingPathComponent("settings.json")
        let data = try! JSONSerialization.data(withJSONObject: oldConfig, options: .prettyPrinted)
        try! data.write(to: URL(fileURLWithPath: path))

        let store = SettingsStore(directory: dir, secretStore: secretStore)
        store.ensureApiKeyLoaded()

        // Should use Keychain key, not the plaintext one
        XCTAssertEqual(store.llmConfig.apiKey, "sk-already-in-keychain")
    }

    func testSetLLMConfigSavesToSecretStore() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let secretStore = InMemorySecretStore()
        let store = SettingsStore(directory: dir, secretStore: secretStore)

        var config = LLMConfig()
        config.endpoint = "https://api.openai.com/v1"
        config.apiKey = "sk-new-key"
        config.modelName = "gpt-4o"
        store.setLLMConfig(config)

        // Key should be in SecretStore
        XCTAssertEqual(secretStore.load(key: "apiKey"), "sk-new-key")

        // Key should NOT be in JSON
        let path = (dir as NSString).appendingPathComponent("settings.json")
        let data = FileManager.default.contents(atPath: path)!
        let dict = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let llm = dict["llmConfig"] as! [String: Any]
        XCTAssertNil(llm["apiKey"], "apiKey must not appear in settings.json")
    }

    func testDeleteKeyWhenEmpty() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let secretStore = InMemorySecretStore()
        try! secretStore.save(key: "apiKey", value: "sk-existing")
        let store = SettingsStore(directory: dir, secretStore: secretStore)

        var config = store.llmConfig
        config.apiKey = ""
        store.setLLMConfig(config)

        XCTAssertNil(secretStore.load(key: "apiKey"), "Empty key should delete from SecretStore")
    }
}
