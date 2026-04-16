import Foundation
@testable import ClaudeSessionHubLib

enum JSONLParserTests {
    static func run() {
        print("── JSONLParserTests ──")
        testReadFirstEntries()
        testReadLastEntries()
        testReadLastEntriesChronologicalOrder()
        testSkipsUnparseableLines()
        testLargeLineSpanningChunkBoundary()
        testLargeLineReverseSpanningChunkBoundary()
        testReadSampledUserTurnsSkipsToolResults()
    }

    // v0.2.8.1 regression: readSampledUserTurns must skip tool_result entries
    // (type=="user" but message.content is an array, not a String). Prior
    // behaviour let them through, which starved the middle-sampler of real
    // user text in heavy-tool sessions and produced tail-biased titles.
    static func testReadSampledUserTurnsSkipsToolResults() {
        let tmp = NSTemporaryDirectory() + "test-sampled-filter-\(UUID().uuidString).jsonl"
        // 70 lines total: 10 head, 10 middle mixed (real text + tool_result), 50 tail
        // skipHead=10, skipTail=50 → middle window is lines 10..<20, size 10
        var lines: [String] = []
        for i in 0..<10 {
            lines.append("{\"type\":\"system\",\"subtype\":\"head\",\"idx\":\(i)}")
        }
        // Middle: alternating real user text and tool_result
        let realTexts = ["关于 coze workflow 的设计问题", "讨论会议记录整理", "需要改进 operator 逻辑", "再确认一下 Selector 的行为", "coze 里这个下拉遮挡怎么解决"]
        for i in 0..<10 {
            if i % 2 == 0 {
                let t = realTexts[i / 2]
                lines.append("{\"type\":\"user\",\"isMeta\":false,\"message\":{\"role\":\"user\",\"content\":\"\(t)\"}}")
            } else {
                // tool_result masquerading as user
                lines.append("{\"type\":\"user\",\"isMeta\":false,\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"content\":\"Dragged from A to B\"}]}}")
            }
        }
        for i in 0..<50 {
            lines.append("{\"type\":\"system\",\"subtype\":\"tail\",\"idx\":\(i)}")
        }
        let content = lines.joined(separator: "\n")
        try! content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let sampled = try! JSONLParser.readSampledUserTurns(at: tmp, count: 5)
        assertEqual(sampled.count, 5, "should pick 5 qualifying user text entries, not tool_results")
        // Every returned entry must have String content — never an array
        for entry in sampled {
            let msg = entry["message"] as? [String: Any]
            let isString = msg?["content"] is String
            check(isString, "sampled entry must have message.content as String, got: \(String(describing: msg?["content"]))")
        }
        // And none of them should be the tool_result stub string
        for entry in sampled {
            let content = (entry["message"] as? [String: Any])?["content"] as? String ?? ""
            check(!content.contains("Dragged from"), "sampled content should NOT be a tool_result payload: \(content)")
        }
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

    // P2 fix: test single JSONL line > 8KB crossing chunk boundary
    static func testLargeLineSpanningChunkBoundary() {
        let tmp = NSTemporaryDirectory() + "test-large-\(UUID().uuidString).jsonl"
        // Create a JSON line that's ~12KB — well over the 8192 chunk size
        let bigValue = String(repeating: "x", count: 12_000)
        let line1 = "{\"type\":\"small\",\"idx\":1}"
        let line2 = "{\"type\":\"big\",\"idx\":2,\"data\":\"\(bigValue)\"}"
        let line3 = "{\"type\":\"small\",\"idx\":3}"
        let content = [line1, line2, line3].joined(separator: "\n")
        try! content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try! JSONLParser.readFirstEntries(at: tmp, count: 10)
        assertEqual(entries.count, 3, "should parse all 3 including >8KB line")
        assertEqual(entries[1]["type"] as? String, "big", "big line should parse correctly")
        assertEqual(entries[1]["idx"] as? Int, 2)
    }

    static func testLargeLineReverseSpanningChunkBoundary() {
        let tmp = NSTemporaryDirectory() + "test-large-rev-\(UUID().uuidString).jsonl"
        let bigValue = String(repeating: "y", count: 12_000)
        let line1 = "{\"type\":\"first\",\"idx\":1}"
        let line2 = "{\"type\":\"big\",\"idx\":2,\"data\":\"\(bigValue)\"}"
        let line3 = "{\"type\":\"last\",\"idx\":3}"
        let content = [line1, line2, line3].joined(separator: "\n")
        try! content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let entries = try! JSONLParser.readLastEntries(at: tmp, count: 2)
        assertEqual(entries.count, 2, "should get last 2 including >8KB line")
        assertEqual(entries[0]["type"] as? String, "big", "big line via reverse scan")
        assertEqual(entries[0]["idx"] as? Int, 2)
        assertEqual(entries[1]["type"] as? String, "last")
    }
}
