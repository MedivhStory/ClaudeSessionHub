import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class TitleStoreTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "titlestore-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSaveAndLoadTitle() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = TitleStore(directory: dir)
        let title = GeneratedTitle(text: "重构 auth", source: .rule, generatedAt: Date())
        store.setTitle(for: "sess-1", title: title)

        let store2 = TitleStore(directory: dir)
        let loaded = store2.currentTitle(for: "sess-1")
        XCTAssertEqual(loaded?.text, "重构 auth")
        XCTAssertEqual(loaded?.source, .rule)
    }

    func testTitleHistoryPreserved() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = TitleStore(directory: dir)
        store.setTitle(for: "sess-1", title: GeneratedTitle(text: "v1", source: .rule, generatedAt: Date()))
        store.setTitle(for: "sess-1", title: GeneratedTitle(text: "v2", source: .rule, generatedAt: Date()))

        let history = store.titleHistory(for: "sess-1")
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.text, "v1")
        XCTAssertEqual(history.last?.text, "v2")
    }

    func testLastProgressSaveAndLoad() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = TitleStore(directory: dir)
        store.setLastProgress(for: "sess-1", progress: "完成了 auth 重构")

        let store2 = TitleStore(directory: dir)
        XCTAssertEqual(store2.lastProgress(for: "sess-1"), "完成了 auth 重构")
    }

    func testUserNoteIndependentOfTitle() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = TitleStore(directory: dir)
        store.setUserNote(for: "sess-1", note: "重要任务，下周继续")

        let store2 = TitleStore(directory: dir)
        XCTAssertEqual(store2.userNote(for: "sess-1"), "重要任务，下周继续")
    }
}
