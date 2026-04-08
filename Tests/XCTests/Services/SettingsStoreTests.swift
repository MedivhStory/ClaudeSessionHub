import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class SettingsStoreTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "settings-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAutoSaveOnPropertyChange() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        store.setSelectedTerminal("iTerm")

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.selectedTerminal, "iTerm")
    }

    func testAutoSaveOnDirectoryChange() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        store.setClaudeDataDirectory("/custom/path")

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.claudeDataDirectory, "/custom/path")
    }

    func testAutoSaveOnIntervalChange() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = SettingsStore(directory: dir)
        store.setScanIntervalSeconds(30)

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.scanIntervalSeconds, 30)
    }
}
