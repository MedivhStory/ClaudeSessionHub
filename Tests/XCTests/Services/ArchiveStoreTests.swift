import XCTest
@testable import ClaudeSessionHubLib

final class ArchiveStoreXCTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "archive-xctest-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testArchiveAndCheck() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = ArchiveStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        XCTAssertFalse(store.isArchived(ref), "should not be archived initially")
        store.archive(ref)
        XCTAssertTrue(store.isArchived(ref), "should be archived after archive()")
    }

    func testPersistence() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = ArchiveStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.archive(ref)

        let store2 = ArchiveStore(directory: dir)
        XCTAssertTrue(store2.isArchived(ref), "archive should persist to disk")
    }

    func testUnarchive() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = ArchiveStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.archive(ref)
        store.unarchive(ref)
        XCTAssertFalse(store.isArchived(ref), "should not be archived after unarchive()")
    }
}
