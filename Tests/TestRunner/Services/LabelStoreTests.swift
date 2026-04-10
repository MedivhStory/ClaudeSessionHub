import Foundation
@testable import ClaudeSessionHubLib

enum LabelStoreTests {
    static func run() {
        print("── LabelStoreTests ──")
        testSetAndGetLabel()
        testPersistsToDisk()
        testRemoveLabel()
        testSettingsStoreDefaultValues()
        testSettingsStorePersistence()
    }

    static func testSetAndGetLabel() {
        let dir = NSTemporaryDirectory() + "label-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = LabelStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.setLabel(for: ref, label: "My Custom Title")
        assertEqual(store.label(for: ref), "My Custom Title")
    }

    static func testPersistsToDisk() {
        let dir = NSTemporaryDirectory() + "label-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = LabelStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.setLabel(for: ref, label: "Persisted")

        let store2 = LabelStore(directory: dir)
        assertEqual(store2.label(for: ref), "Persisted", "label should persist across instances")
    }

    static func testRemoveLabel() {
        let dir = NSTemporaryDirectory() + "label-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = LabelStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.setLabel(for: ref, label: "Temp")
        store.setLabel(for: ref, label: nil)
        check(store.label(for: ref) == nil, "label should be nil after removal")
    }

    static func testSettingsStoreDefaultValues() {
        let dir = NSTemporaryDirectory() + "settings-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir, secretStore: InMemorySecretStore())
        assertEqual(store.selectedTerminal, "Ghostty", "default terminal")
        assertEqual(store.scanIntervalSeconds, 60, "default scan interval")
    }

    static func testSettingsStorePersistence() {
        let dir = NSTemporaryDirectory() + "settings-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let secrets = InMemorySecretStore()

        let store = SettingsStore(directory: dir, secretStore: secrets)
        store.selectedTerminal = "Terminal"
        store.scanIntervalSeconds = 120
        store.save()

        let store2 = SettingsStore(directory: dir, secretStore: secrets)
        assertEqual(store2.selectedTerminal, "Terminal", "terminal should persist")
        assertEqual(store2.scanIntervalSeconds, 120, "interval should persist")
    }
}
