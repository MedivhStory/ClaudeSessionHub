import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class UnderstandingStoreTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "understanding-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSaveAndLoadSnapshot() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "AI标题", progress: "完成了重构",
            summary: "摘要文本", modelName: "gpt-4o",
            generatedAt: Date(), basedOnLastActiveAt: Date()
        )
        store.setSnapshot(snapshot)

        let store2 = UnderstandingStore(directory: dir)
        let loaded = store2.snapshot(for: "s1")
        XCTAssertEqual(loaded?.title, "AI标题")
        XCTAssertEqual(loaded?.progress, "完成了重构")
        XCTAssertEqual(loaded?.summary, "摘要文本")
    }

    func testSnapshotDedup() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        let now = Date()
        let s1 = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "Same", progress: nil,
            summary: nil, modelName: "m",
            generatedAt: now, basedOnLastActiveAt: now
        )
        store.setSnapshot(s1)
        store.setSnapshot(s1)

        let loaded = store.snapshot(for: "s1")
        XCTAssertEqual(loaded?.title, "Same")
    }

    func testHasEnhancement() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        XCTAssertFalse(store.hasEnhancement(for: "s1"))

        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "T", progress: nil,
            summary: nil, modelName: "m",
            generatedAt: Date(), basedOnLastActiveAt: Date()
        )
        store.setSnapshot(snapshot)
        XCTAssertTrue(store.hasEnhancement(for: "s1"))
    }

    func testSameContentRefreshClearsStale() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        let oldDate = Date(timeIntervalSinceNow: -3600)
        let now = Date()

        // Initial snapshot based on old activity
        let s1 = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "Same Title", progress: "Same Progress",
            summary: nil, modelName: "m",
            generatedAt: oldDate, basedOnLastActiveAt: oldDate
        )
        store.setSnapshot(s1)
        XCTAssertTrue(store.isStale(for: "s1", lastActiveAt: now), "Should be stale after new activity")

        // Refresh returns same text but updated basedOnLastActiveAt
        let s2 = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "Same Title", progress: "Same Progress",
            summary: nil, modelName: "m",
            generatedAt: now, basedOnLastActiveAt: now
        )
        store.setSnapshot(s2)
        XCTAssertFalse(store.isStale(for: "s1", lastActiveAt: now), "Must not be stale after refresh — even with same text")
    }

    func testIsStale() {
        let dir = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = UnderstandingStore(directory: dir)
        let oldDate = Date(timeIntervalSinceNow: -3600)
        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "T", progress: nil,
            summary: nil, modelName: "m",
            generatedAt: oldDate, basedOnLastActiveAt: oldDate
        )
        store.setSnapshot(snapshot)

        // Session active after snapshot → stale
        XCTAssertTrue(store.isStale(for: "s1", lastActiveAt: Date()))
        // Session active before snapshot → not stale
        XCTAssertFalse(store.isStale(for: "s1", lastActiveAt: oldDate))
        // No snapshot → not stale (nothing to be stale)
        XCTAssertFalse(store.isStale(for: "s2", lastActiveAt: Date()))
    }
}
