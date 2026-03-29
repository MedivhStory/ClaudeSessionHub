import Foundation
@testable import ClaudeSessionHubLib

enum JSONLParserTests {
    static func run() {
        print("── JSONLParserTests ──")
        testReadFirstEntries()
        testReadLastEntries()
        testReadLastEntriesChronologicalOrder()
        testSkipsUnparseableLines()
    }

    static func testReadFirstEntries() {
        let tmp = NSTemporaryDirectory() + "test-first-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-01"}
        {"type":"assistant","message":{"role":"assistant","content":"hi"},"timestamp":"2026-03-02"}
        {"type":"user","message":{"role":"user","content":"bye"},"timestamp":"2026-03-03"}
        """
        try! content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try! JSONLParser.readFirstEntries(at: tmp, count: 2)
        assertEqual(entries.count, 2, "should read exactly 2 entries")
        assertEqual(entries[0]["type"] as? String, "user")
        assertEqual(entries[1]["type"] as? String, "assistant")
    }

    static func testReadLastEntries() {
        let tmp = NSTemporaryDirectory() + "test-last-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"user","timestamp":"1"}
        {"type":"assistant","timestamp":"2"}
        {"type":"user","timestamp":"3"}
        {"type":"assistant","timestamp":"4"}
        {"type":"user","timestamp":"5"}
        """
        try! content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try! JSONLParser.readLastEntries(at: tmp, count: 2)
        assertEqual(entries.count, 2, "should read exactly 2 entries")
        // Should be in chronological order (4, 5), not reverse
        assertEqual(entries[0]["timestamp"] as? String, "4")
        assertEqual(entries[1]["timestamp"] as? String, "5")
    }

    static func testReadLastEntriesChronologicalOrder() {
        let tmp = NSTemporaryDirectory() + "test-chrono-\(UUID().uuidString).jsonl"
        var lines: [String] = []
        for i in 1...100 {
            lines.append("{\"idx\":\(i)}")
        }
        try! lines.joined(separator: "\n").write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try! JSONLParser.readLastEntries(at: tmp, count: 3)
        assertEqual(entries.count, 3)
        assertEqual(entries[0]["idx"] as? Int, 98, "first of last 3 should be 98")
        assertEqual(entries[1]["idx"] as? Int, 99)
        assertEqual(entries[2]["idx"] as? Int, 100, "last should be 100")
    }

    static func testSkipsUnparseableLines() {
        let tmp = NSTemporaryDirectory() + "test-corrupt-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        THIS IS NOT JSON
        {"type":"assistant","message":{"role":"assistant","content":"hi"}}
        """
        try! content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try! JSONLParser.readFirstEntries(at: tmp, count: 10)
        assertEqual(entries.count, 2, "corrupt line should be skipped")
    }
}
