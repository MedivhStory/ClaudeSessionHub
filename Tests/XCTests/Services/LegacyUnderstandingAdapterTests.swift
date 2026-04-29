import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class LegacyUnderstandingAdapterTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-legacy-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func writeV1JSON(_ dict: [String: Any], dir: String) {
        let path = dir + "/understanding.json"
        let data = try! JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try! data.write(to: URL(fileURLWithPath: path))
    }

    private func mtime(of path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }

    // MARK: - Missing file

    func testMissingFileReturnsNil() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let adapter = LegacyUnderstandingAdapter(directory: dir)
        XCTAssertNil(adapter.legacySnapshot(for: "any"))
    }

    func testMissingDirectoryReturnsNil() {
        let adapter = LegacyUnderstandingAdapter(
            directory: NSTemporaryDirectory() + "csh-legacy-nonexistent-\(UUID().uuidString)"
        )
        XCTAssertNil(adapter.legacySnapshot(for: "any"))
    }

    // MARK: - Valid V1 read via the production V1 writer

    func testReadsV1DataWrittenByUnderstandingStore() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UnderstandingStore(directory: dir)
        let snap = LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "test title",
            progress: "in progress",
            summary: "test summary",
            modelName: "gpt-4o",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            basedOnLastActiveAt: Date()
        )
        store.setSnapshot(snap)

        let adapter = LegacyUnderstandingAdapter(directory: dir)
        let legacy = adapter.legacySnapshot(for: "s1")
        XCTAssertNotNil(legacy)
        XCTAssertEqual(legacy?.title, "test title")
        XCTAssertEqual(legacy?.progress, "in progress")
        XCTAssertEqual(legacy?.summary, "test summary")
        XCTAssertEqual(legacy?.modelName, "gpt-4o")
        XCTAssertNotNil(legacy?.generatedAt)
    }

    // MARK: - Partial fields

    func testPartialTitleOnly() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        // Write JSON manually because the strict v1 model requires
        // title + modelName + generatedAt; we want a truly partial record.
        writeV1JSON(
            ["s1": ["title": "only title"]],
            dir: dir
        )

        let adapter = LegacyUnderstandingAdapter(directory: dir)
        let legacy = adapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "only title")
        XCTAssertNil(legacy?.progress)
        XCTAssertNil(legacy?.summary)
        XCTAssertNil(legacy?.modelName)
        XCTAssertNil(legacy?.generatedAt)
    }

    func testPartialTitleAndProgress() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeV1JSON(
            ["s1": ["title": "t", "progress": "p"]],
            dir: dir
        )
        let adapter = LegacyUnderstandingAdapter(directory: dir)
        let legacy = adapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "t")
        XCTAssertEqual(legacy?.progress, "p")
        XCTAssertNil(legacy?.summary)
    }

    func testFullTitleProgressSummary() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeV1JSON(
            ["s1": ["title": "t", "progress": "p", "summary": "s"]],
            dir: dir
        )
        let adapter = LegacyUnderstandingAdapter(directory: dir)
        let legacy = adapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "t")
        XCTAssertEqual(legacy?.progress, "p")
        XCTAssertEqual(legacy?.summary, "s")
        XCTAssertNil(legacy?.generatedAt)
    }

    // MARK: - Absent generatedAt

    func testAbsentGeneratedAtIsNil() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeV1JSON(
            ["s1": ["title": "t", "progress": "p", "summary": "s", "modelName": "m"]],
            dir: dir
        )
        let adapter = LegacyUnderstandingAdapter(directory: dir)
        let legacy = adapter.legacySnapshot(for: "s1")
        XCTAssertNotNil(legacy)
        XCTAssertEqual(legacy?.title, "t")
        XCTAssertEqual(legacy?.modelName, "m")
        XCTAssertNil(legacy?.generatedAt)
    }

    // MARK: - Multiple sessions

    func testMultipleSessionsIndependent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeV1JSON(
            [
                "s1": ["title": "a"],
                "s2": ["title": "b", "progress": "p2"]
            ],
            dir: dir
        )
        let adapter = LegacyUnderstandingAdapter(directory: dir)
        XCTAssertEqual(adapter.legacySnapshot(for: "s1")?.title, "a")
        XCTAssertEqual(adapter.legacySnapshot(for: "s2")?.title, "b")
        XCTAssertEqual(adapter.legacySnapshot(for: "s2")?.progress, "p2")
        XCTAssertNil(adapter.legacySnapshot(for: "ghost"))
    }

    // MARK: - Never writes (mtime preserved)

    func testReadDoesNotMutateFile() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UnderstandingStore(directory: dir)
        store.setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "t",
            progress: nil,
            summary: nil,
            modelName: "m",
            generatedAt: Date(),
            basedOnLastActiveAt: Date()
        ))

        let path = dir + "/understanding.json"
        // Force mtime to a known past value so any write would be detectable.
        let pastDate = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: path
        )
        let mtimeBefore = mtime(of: path)!
        let dataBefore = try Data(contentsOf: URL(fileURLWithPath: path))

        // Multiple read-only accesses — none of these should touch the file.
        let adapter = LegacyUnderstandingAdapter(directory: dir)
        _ = adapter.legacySnapshot(for: "s1")
        _ = adapter.legacySnapshot(for: "ghost")
        _ = adapter.legacySnapshot(for: "s1")
        adapter.invalidateCache()
        _ = adapter.legacySnapshot(for: "s1") // forces re-read from disk

        let mtimeAfter = mtime(of: path)!
        let dataAfter = try Data(contentsOf: URL(fileURLWithPath: path))

        XCTAssertEqual(
            mtimeBefore,
            mtimeAfter,
            "understanding.json mtime must not change after read-only access"
        )
        XCTAssertEqual(dataBefore, dataAfter, "file contents must be unchanged")
    }
}
