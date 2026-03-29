import XCTest
@testable import ClaudeSessionHubLib

final class JSONLParserXCTests: XCTestCase {

    func testReadFirstEntries() throws {
        let tmp = NSTemporaryDirectory() + "test-first-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-01"}
        {"type":"assistant","message":{"role":"assistant","content":"hi"},"timestamp":"2026-03-02"}
        {"type":"user","message":{"role":"user","content":"bye"},"timestamp":"2026-03-03"}
        """
        try content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try JSONLParser.readFirstEntries(at: tmp, count: 2)
        XCTAssertEqual(entries.count, 2, "should read exactly 2 entries")
        XCTAssertEqual(entries[0]["type"] as? String, "user")
        XCTAssertEqual(entries[1]["type"] as? String, "assistant")
    }

    func testReadLastEntries() throws {
        let tmp = NSTemporaryDirectory() + "test-last-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"user","timestamp":"1"}
        {"type":"assistant","timestamp":"2"}
        {"type":"user","timestamp":"3"}
        {"type":"assistant","timestamp":"4"}
        {"type":"user","timestamp":"5"}
        """
        try content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try JSONLParser.readLastEntries(at: tmp, count: 2)
        XCTAssertEqual(entries.count, 2, "should read exactly 2 entries")
        XCTAssertEqual(entries[0]["timestamp"] as? String, "4")
        XCTAssertEqual(entries[1]["timestamp"] as? String, "5")
    }

    func testReadLastEntriesChronologicalOrder() throws {
        let tmp = NSTemporaryDirectory() + "test-chrono-\(UUID().uuidString).jsonl"
        var lines: [String] = []
        for i in 1...100 {
            lines.append("{\"idx\":\(i)}")
        }
        try lines.joined(separator: "\n").write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try JSONLParser.readLastEntries(at: tmp, count: 3)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0]["idx"] as? Int, 98, "first of last 3 should be 98")
        XCTAssertEqual(entries[1]["idx"] as? Int, 99)
        XCTAssertEqual(entries[2]["idx"] as? Int, 100, "last should be 100")
    }

    func testSkipsUnparseableLines() throws {
        let tmp = NSTemporaryDirectory() + "test-corrupt-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        THIS IS NOT JSON
        {"type":"assistant","message":{"role":"assistant","content":"hi"}}
        """
        try content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try JSONLParser.readFirstEntries(at: tmp, count: 10)
        XCTAssertEqual(entries.count, 2, "corrupt line should be skipped")
    }

    func testWithSampleFixture() throws {
        let bundle = Bundle(for: type(of: self))
        guard let fixturePath = bundle.path(forResource: "sample-session", ofType: "jsonl", inDirectory: "Fixtures") else {
            XCTFail("sample-session.jsonl fixture not found in bundle")
            return
        }

        let first = try JSONLParser.readFirstEntries(at: fixturePath, count: 5)
        XCTAssertGreaterThan(first.count, 0, "should read at least 1 entry from fixture")

        let last = try JSONLParser.readLastEntries(at: fixturePath, count: 5)
        XCTAssertGreaterThan(last.count, 0, "should read at least 1 entry from fixture")
    }
}
