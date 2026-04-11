import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

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
        guard let fixtureURL = Bundle.module.url(forResource: "sample-session", withExtension: "jsonl", subdirectory: "Fixtures") else {
            XCTFail("sample-session.jsonl fixture not found in bundle")
            return
        }
        let fixturePath = fixtureURL.path

        let first = try JSONLParser.readFirstEntries(at: fixturePath, count: 5)
        XCTAssertGreaterThan(first.count, 0, "should read at least 1 entry from fixture")

        let last = try JSONLParser.readLastEntries(at: fixturePath, count: 5)
        XCTAssertGreaterThan(last.count, 0, "should read at least 1 entry from fixture")
    }

    // MARK: - readSampledUserTurns tests (Task 4.1)

    private func writeJSONL(lines: [String]) throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("test.jsonl").path
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func test_readSampledUserTurns_emptyFile_returnsEmpty() throws {
        let path = try writeJSONL(lines: [])
        // Empty file should produce 0 total lines; function returns []
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        XCTAssertTrue(result.isEmpty)
    }

    func test_readSampledUserTurns_fileSmallerThanSkipSum_returnsEmpty() throws {
        // skipHead=10 + skipTail=50 = 60; write only 5 lines
        let lines = (0..<5).map { "{\"type\":\"user\",\"isMeta\":false,\"content\":\"line \($0)\"}" }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        XCTAssertTrue(result.isEmpty)
    }

    func test_readSampledUserTurns_middleSmallerThanK_returnsAll() throws {
        // 70 lines: skip 10 head + 50 tail = 10 in middle; request K=20
        var lines: [String] = []
        for i in 0..<70 {
            lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"m\(i)\"}")
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 20)
        // middleSize = 10, actualK = min(20, 10) = 10
        XCTAssertEqual(result.count, 10)
    }

    func test_readSampledUserTurns_deterministicBucketSelection() throws {
        // Same input, two calls → identical output
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"m\(i)\"}")
        }
        let path = try writeJSONL(lines: lines)
        let a = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        let b = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        XCTAssertEqual(a.count, b.count)
        // Compare content field across both results
        let aContents = a.compactMap { $0["content"] as? String }
        let bContents = b.compactMap { $0["content"] as? String }
        XCTAssertEqual(aContents, bContents)
    }

    func test_readSampledUserTurns_selectsNearestBucketCenter() throws {
        // 100 lines, K=5, skipHead=10, skipTail=50 → middleSize=40, middleStart=10, middleEnd=60
        // bucketWidth=40/5=8, centers at middleStart + (i+0.5)*8 = 14, 22, 30, 38, 46
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"\(i)\"}")
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        let picked = result.compactMap { $0["content"] as? String }
        // Should pick lines closest to centers 14, 22, 30, 38, 46
        XCTAssertEqual(picked, ["14", "22", "30", "38", "46"])
    }

    func test_readSampledUserTurns_tieDistance_prefersEarlier() throws {
        // Construct a case where bucket center falls between two equally-distant
        // qualifying user turns. Earlier one should win (stream order).
        // Setup: 70 lines, skipHead=10, skipTail=50, middleSize=10
        // With K=1, bucketWidth=10, center = 10 + 0.5*10 = 15 (single bucket)
        // Actually single bucket center will just match the center line —
        // for a tie case, we need two lines equidistant from center with one
        // being assistant (non-qualifying) in between.
        // Simpler: K=2, middleSize=10, bucketWidth=5, centers at 12.5→12, 17.5→17
        // First bucket at 12: line 12 is qualifying user → returns 12
        // That doesn't demonstrate tie-breaking explicitly. Use a more direct case:
        //
        // K=2 with 4 qualifying lines in middle at indices 11,13,15,17
        // bucketWidth=5, centers: middleStart+2=12, middleStart+7=17
        // Bucket 0 center=12; candidates in bucket [10,15): indices 11, 13
        // |11-12|=1, |13-12|=1 → tie; earlier wins → 11
        // Bucket 1 center=17; candidates in bucket [15,20): indices 15, 17
        // |15-17|=2, |17-17|=0 → 17 wins
        var lines: [String] = []
        for i in 0..<70 {
            // Indices 11, 13, 15, 17 are user; others are assistant (non-qualifying)
            if [11, 13, 15, 17].contains(i) {
                lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"u\(i)\"}")
            } else {
                lines.append("{\"type\":\"assistant\",\"content\":\"a\(i)\"}")
            }
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 2)
        let picked = result.compactMap { $0["content"] as? String }
        XCTAssertEqual(picked, ["u11", "u17"])
    }

    func test_readSampledUserTurns_skipsMetaUsers() throws {
        // 100 lines; every 5th is isMeta=true (should be skipped)
        var lines: [String] = []
        for i in 0..<100 {
            let isMeta = (i % 5 == 0)
            lines.append("{\"type\":\"user\",\"isMeta\":\(isMeta),\"content\":\"\(i)\"}")
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        let picked = result.compactMap { $0["content"] as? String }.compactMap { Int($0) }
        // No picked index should be a multiple of 5
        for idx in picked {
            XCTAssertNotEqual(idx % 5, 0, "picked meta user at index \(idx)")
        }
    }

    func test_readSampledUserTurns_skipsAssistantEntries() throws {
        // 100 lines; even indices are user, odd are assistant
        var lines: [String] = []
        for i in 0..<100 {
            if i % 2 == 0 {
                lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"u\(i)\"}")
            } else {
                lines.append("{\"type\":\"assistant\",\"content\":\"a\(i)\"}")
            }
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        for entry in result {
            XCTAssertEqual(entry["type"] as? String, "user")
        }
    }

    func test_readSampledUserTurns_emptyBucketsReturnFewer() throws {
        // 100 lines, but only one qualifying user turn in the middle window
        var lines: [String] = []
        for i in 0..<100 {
            if i == 30 {
                lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"lonely\"}")
            } else {
                lines.append("{\"type\":\"assistant\",\"content\":\"a\(i)\"}")
            }
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        // Only 1 qualifying user turn in middle (at index 30) — result has ≤1 entry
        XCTAssertLessThanOrEqual(result.count, 1)
        if result.count == 1 {
            XCTAssertEqual(result[0]["content"] as? String, "lonely")
        }
    }

    func test_readSampledUserTurns_malformedJSONLines_skipped() throws {
        // Mix valid JSON with a few corrupt lines; parser should skip corrupt, not crash
        var lines: [String] = []
        for i in 0..<100 {
            if i == 30 {
                lines.append("this is not json")
            } else {
                lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"\(i)\"}")
            }
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        // Should not throw; should return valid user turns (skipping the malformed line)
        XCTAssertGreaterThan(result.count, 0)
        // The malformed line at index 30 must NOT appear
        for entry in result {
            let content = entry["content"] as? String
            XCTAssertNotNil(content)
        }
    }

    func test_readSampledUserTurns_missingTrailingNewline() throws {
        // Write JSONL without trailing \n on the last line; Pass 1 must count the last line
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"\(i)\"}")
        }
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("test.jsonl").path
        // Join without trailing newline
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        // With 100 lines, skip 10+50=60, middleSize=40, K=5 → returns 5 entries
        XCTAssertEqual(result.count, 5)
    }

    func test_readSampledUserTurns_largeFile_correctness() throws {
        // 10k synthetic lines, all qualifying user turns
        var lines: [String] = []
        for i in 0..<10_000 {
            lines.append("{\"type\":\"user\",\"isMeta\":false,\"content\":\"\(i)\"}")
        }
        let path = try writeJSONL(lines: lines)
        let result = try JSONLParser.readSampledUserTurns(at: path, count: 5)
        // Should return exactly 5 entries evenly distributed in middle window
        XCTAssertEqual(result.count, 5)
        // Contents should all be valid integers from within the middle window
        let middleStart = 10
        let middleEnd = 10_000 - 50
        for entry in result {
            guard let content = entry["content"] as? String, let idx = Int(content) else {
                XCTFail("expected integer content, got \(entry)")
                continue
            }
            XCTAssertGreaterThanOrEqual(idx, middleStart)
            XCTAssertLessThan(idx, middleEnd)
        }
    }
}
