import Foundation
@testable import ClaudeSessionHubLib

enum ArchiveStoreTests {
    static func run() {
        print("── ArchiveStoreTests ──")
        testArchiveAndCheck()
        testPersistence()
        testUnarchive()
    }

    static func testArchiveAndCheck() {
        let dir = NSTemporaryDirectory() + "archive-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = ArchiveStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        check(!store.isArchived(ref), "should not be archived initially")
        store.archive(ref)
        check(store.isArchived(ref), "should be archived after archive()")
    }

    static func testPersistence() {
        let dir = NSTemporaryDirectory() + "archive-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = ArchiveStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.archive(ref)

        let store2 = ArchiveStore(directory: dir)
        check(store2.isArchived(ref), "archive should persist to disk")
    }

    static func testUnarchive() {
        let dir = NSTemporaryDirectory() + "archive-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = ArchiveStore(directory: dir)
        let ref = SessionRef(providerID: "claude", sessionID: "abc-123")
        store.archive(ref)
        store.unarchive(ref)
        check(!store.isArchived(ref), "should not be archived after unarchive()")
    }
}
