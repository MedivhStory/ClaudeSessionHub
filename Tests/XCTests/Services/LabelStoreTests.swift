import XCTest
@testable import ClaudeSessionHubLib

final class LabelStoreXCTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "label-xctest-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSetAndGetLabel() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = LabelStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.setLabel(for: ref, label: "My Custom Title")
        XCTAssertEqual(store.label(for: ref), "My Custom Title")
    }

    func testPersistsToDisk() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = LabelStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.setLabel(for: ref, label: "Persisted")

        let store2 = LabelStore(directory: dir)
        XCTAssertEqual(store2.label(for: ref), "Persisted", "label should persist across instances")
    }

    func testRemoveLabel() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = LabelStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.setLabel(for: ref, label: "Temp")
        store.setLabel(for: ref, label: nil)
        XCTAssertNil(store.label(for: ref), "label should be nil after removal")
    }

    func testSettingsStoreDefaultValues() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        XCTAssertEqual(store.selectedTerminal, "Ghostty", "default terminal")
        XCTAssertEqual(store.scanIntervalSeconds, 60, "default scan interval")
    }

    func testSettingsStorePersistence() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        store.selectedTerminal = "Terminal"
        store.scanIntervalSeconds = 120
        store.save()

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.selectedTerminal, "Terminal", "terminal should persist")
        XCTAssertEqual(store2.scanIntervalSeconds, 120, "interval should persist")
    }
}
