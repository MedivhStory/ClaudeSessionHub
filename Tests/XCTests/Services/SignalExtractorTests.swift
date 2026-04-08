import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class SignalExtractorTests: XCTestCase {

    private func createTempDir() -> String {
        let dir = NSTemporaryDirectory() + "signal-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - history.jsonl

    func testExtractHistoryDisplayTexts() throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let historyLines = [
            #"{"display":"帮我重构 auth middleware","timestamp":1775536107472,"project":"/test","sessionId":"sess-1"}"#,
            #"{"display":"fix the login bug","timestamp":1775536207472,"project":"/test","sessionId":"sess-1"}"#,
            #"{"display":"unrelated task","timestamp":1775536307472,"project":"/other","sessionId":"sess-2"}"#
        ]
        try historyLines.joined(separator: "\n")
            .write(toFile: base + "/history.jsonl", atomically: true, encoding: .utf8)

        let extractor = SignalExtractor(baseDirectory: base)
        let texts = extractor.historyDisplayTexts(for: "sess-1")

        XCTAssertEqual(texts.count, 2)
        XCTAssertEqual(texts.first, "帮我重构 auth middleware")
        XCTAssertEqual(texts.last, "fix the login bug")
    }

    func testHistoryReturnsEmptyWhenNoFile() {
        let extractor = SignalExtractor(baseDirectory: "/nonexistent")
        let texts = extractor.historyDisplayTexts(for: "any")
        XCTAssertEqual(texts, [])
    }

    // MARK: - tasks/

    func testExtractTaskSignals() throws {
        let base = createTempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }

        let tasksDir = base + "/tasks/sess-1"
        try FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)

        let task1: [String: Any] = [
            "id": "1",
            "subject": "Refactor auth to protocol-based",
            "description": "Split middleware into protocol conformances",
            "status": "completed"
        ]
        let task2: [String: Any] = [
            "id": "2",
            "subject": "Add unit tests for new auth",
            "description": "Cover edge cases",
            "status": "in_progress"
        ]
        try JSONSerialization.data(withJSONObject: task1)
            .write(to: URL(fileURLWithPath: tasksDir + "/1.json"))
        try JSONSerialization.data(withJSONObject: task2)
            .write(to: URL(fileURLWithPath: tasksDir + "/2.json"))

        let extractor = SignalExtractor(baseDirectory: base)
        let signals = extractor.taskSignals(for: "sess-1")

        XCTAssertEqual(signals.count, 2)
        let inProgress = signals.first { $0.status == "in_progress" }
        XCTAssertEqual(inProgress?.subject, "Add unit tests for new auth")
    }

    func testTasksReturnsEmptyWhenNoDir() {
        let extractor = SignalExtractor(baseDirectory: "/nonexistent")
        let signals = extractor.taskSignals(for: "any")
        XCTAssertEqual(signals, [])
    }
}
