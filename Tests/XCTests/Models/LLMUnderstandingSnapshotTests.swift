import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LLMUnderstandingSnapshotTests: XCTestCase {

    func testSnapshotProperties() {
        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "test-1",
            title: "重构认证中间件",
            progress: "完成了 protocol 化重构",
            summary: "这个 session 在重构 auth middleware。已完成协议抽象，待补测试。",
            modelName: "gpt-4o",
            generatedAt: Date(),
            basedOnLastActiveAt: Date()
        )
        XCTAssertEqual(snapshot.sessionID, "test-1")
        XCTAssertEqual(snapshot.title, "重构认证中间件")
        XCTAssertEqual(snapshot.progress, "完成了 protocol 化重构")
        XCTAssertNotNil(snapshot.summary)
        XCTAssertEqual(snapshot.modelName, "gpt-4o")
    }

    func testSnapshotCodable() throws {
        let now = Date()
        let snapshot = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "Test", progress: "Done",
            summary: "Summary", modelName: "model",
            generatedAt: now, basedOnLastActiveAt: now
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LLMUnderstandingSnapshot.self, from: data)
        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.progress, "Done")
        XCTAssertEqual(decoded.summary, "Summary")
    }

    func testSnapshotEquatable() {
        let now = Date()
        let s1 = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "T", progress: "P",
            summary: "S", modelName: "m",
            generatedAt: now, basedOnLastActiveAt: now
        )
        let s2 = LLMUnderstandingSnapshot(
            sessionID: "s1", title: "T", progress: "P",
            summary: "S", modelName: "m",
            generatedAt: now, basedOnLastActiveAt: now
        )
        XCTAssertEqual(s1, s2)
    }
}
