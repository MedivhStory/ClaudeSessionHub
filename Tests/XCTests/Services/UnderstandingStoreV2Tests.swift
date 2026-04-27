import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class UnderstandingStoreV2Tests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-v2-store-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Empty / missing store

    func testEmptyStoreLoadsAsEmpty() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        XCTAssertNil(store.state(for: "any-id"))
    }

    func testMissingDirectoryDoesNotCrashOnLoad() {
        let store = UnderstandingStoreV2(directory: NSTemporaryDirectory() + "csh-v2-nonexistent-\(UUID().uuidString)")
        XCTAssertNil(store.state(for: "any"))
    }

    // MARK: - Schema version

    func testSchemaVersionWrittenInFile() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, ai)

        let path = dir + "/understanding-v2.json"
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["schemaVersion"] as? String, "1")
    }

    // MARK: - Encode / decode round trip

    func testRoundTripPersistArtifact() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store1 = UnderstandingStoreV2(directory: dir)
        let artifact = UnderstandingArtifact(
            value: "hello",
            source: .ai,
            trigger: .manualGenerate,
            sessionFingerprint: "fp1",
            staleState: .fresh,
            modelName: "gpt-4o"
        )
        store1.appendArtifact(for: "s1", field: .title, artifact)

        let store2 = UnderstandingStoreV2(directory: dir)
        let state = store2.state(for: "s1")
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.titleVersions.count, 1)
        XCTAssertEqual(state?.titleVersions.first?.value, "hello")
        XCTAssertEqual(state?.titleVersions.first?.modelName, "gpt-4o")
        XCTAssertEqual(state?.titleVersions.first?.sessionFingerprint, "fp1")
        XCTAssertEqual(state?.currentTitleVersionID, artifact.id)
    }

    func testRoundTripStaleStateAssociatedValues() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let store1 = UnderstandingStoreV2(directory: dir)
        let a1 = UnderstandingArtifact(
            value: "a", source: .ai, trigger: .manualGenerate,
            staleState: .staleSessionUpdated(at: when)
        )
        let a2 = UnderstandingArtifact(
            value: "b", source: .ai, trigger: .manualGenerate,
            staleState: .stalePartial(reason: "edited")
        )
        let a3 = UnderstandingArtifact(
            value: "c", source: .ai, trigger: .manualGenerate,
            staleState: .legacyUnknown
        )
        store1.appendArtifact(for: "s1", field: .title, a1)
        store1.appendArtifact(for: "s1", field: .progress, a2)
        store1.appendArtifact(for: "s1", field: .summary, a3)

        let store2 = UnderstandingStoreV2(directory: dir)
        let state = store2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.first?.staleState, .staleSessionUpdated(at: when))
        XCTAssertEqual(state.progressVersions.first?.staleState, .stalePartial(reason: "edited"))
        XCTAssertEqual(state.summaryVersions.first?.staleState, .legacyUnknown)
    }

    func testRoundTripSelectionEvent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store1 = UnderstandingStoreV2(directory: dir)
        let prev = UUID()
        let target = UUID()
        let event = SelectionEvent(
            field: .title,
            action: .adopt,
            previousVersionID: prev,
            targetVersionID: target
        )
        store1.appendSelectionEvent(for: "s1", event)

        let store2 = UnderstandingStoreV2(directory: dir)
        let state = store2.state(for: "s1")!
        XCTAssertEqual(state.selectionEvents.count, 1)
        XCTAssertEqual(state.selectionEvents.first?.previousVersionID, prev)
        XCTAssertEqual(state.selectionEvents.first?.targetVersionID, target)
        XCTAssertEqual(state.selectionEvents.first?.field, .title)
        XCTAssertEqual(state.selectionEvents.first?.action, .adopt)
    }

    func testRoundTripSelectionEventNilPrevious() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store1 = UnderstandingStoreV2(directory: dir)
        let target = UUID()
        let event = SelectionEvent(
            field: .progress, action: .adopt,
            previousVersionID: nil, targetVersionID: target
        )
        store1.appendSelectionEvent(for: "s1", event)

        let store2 = UnderstandingStoreV2(directory: dir)
        let state = store2.state(for: "s1")!
        XCTAssertNil(state.selectionEvents.first?.previousVersionID)
        XCTAssertEqual(state.selectionEvents.first?.targetVersionID, target)
    }

    // MARK: - Pointer rules

    func testAppendAIWhenPointerNilMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai = UnderstandingArtifact(value: "ai", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, ai)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, ai.id)
    }

    func testAppendAIWhenPointerOnAIMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai1 = UnderstandingArtifact(value: "1", source: .ai, trigger: .manualGenerate)
        let ai2 = UnderstandingArtifact(value: "2", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, ai1)
        store.appendArtifact(for: "s1", field: .title, ai2)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, ai2.id)
        XCTAssertEqual(store.state(for: "s1")?.titleVersions.count, 2)
    }

    func testAppendAIWhenPointerOnManualDoesNotMove() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let manual = UnderstandingArtifact(value: "m", source: .manual, trigger: .manualEdit)
        let ai = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, manual)
        store.appendArtifact(for: "s1", field: .title, ai)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, manual.id)
        XCTAssertEqual(store.state(for: "s1")?.titleVersions.count, 2)
    }

    func testAppendManualAlwaysMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        let manual = UnderstandingArtifact(value: "m", source: .manual, trigger: .manualEdit)
        store.appendArtifact(for: "s1", field: .title, ai)
        store.appendArtifact(for: "s1", field: .title, manual)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, manual.id)
    }

    func testAppendManualOverManualMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let m1 = UnderstandingArtifact(value: "m1", source: .manual, trigger: .manualEdit)
        let m2 = UnderstandingArtifact(value: "m2", source: .manual, trigger: .manualEdit)
        store.appendArtifact(for: "s1", field: .title, m1)
        store.appendArtifact(for: "s1", field: .title, m2)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, m2.id)
    }

    func testSummaryAIAlwaysMovesPointer() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai1 = UnderstandingArtifact(value: "1", source: .ai, trigger: .manualGenerate)
        let ai2 = UnderstandingArtifact(value: "2", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .summary, ai1)
        store.appendArtifact(for: "s1", field: .summary, ai2)
        XCTAssertEqual(store.state(for: "s1")?.currentSummaryVersionID, ai2.id)
    }

    // MARK: - setCurrentPointer

    func testSetCurrentPointerToValidVersion() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let manual = UnderstandingArtifact(value: "m", source: .manual, trigger: .manualEdit)
        let ai = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, manual)
        store.appendArtifact(for: "s1", field: .title, ai)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, manual.id)

        try store.setCurrentPointer(for: "s1", field: .title, to: ai.id)
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, ai.id)
    }

    func testSetCurrentPointerThrowsForUnknownVersion() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, ai)
        let unknown = UUID()

        XCTAssertThrowsError(try store.setCurrentPointer(for: "s1", field: .title, to: unknown)) { err in
            guard let storeErr = err as? UnderstandingStoreV2.StoreError else {
                XCTFail("expected StoreError")
                return
            }
            if case .versionNotFound(let field, let id) = storeErr {
                XCTAssertEqual(field, .title)
                XCTAssertEqual(id, unknown)
            } else {
                XCTFail("expected versionNotFound")
            }
        }
        // Pointer must remain unchanged.
        XCTAssertEqual(store.state(for: "s1")?.currentTitleVersionID, ai.id)
    }

    func testSetCurrentPointerThrowsForUnknownSession() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        XCTAssertThrowsError(try store.setCurrentPointer(for: "ghost", field: .title, to: UUID()))
        XCTAssertNil(store.state(for: "ghost"))
    }

    // MARK: - Legacy not persisted in V2

    func testLegacySnapshotNotPersistedInV2() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let ai = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, ai)

        let path = dir + "/understanding-v2.json"
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let states = json["states"] as! [String: Any]
        let s1 = states["s1"] as! [String: Any]
        XCTAssertNil(s1["legacySnapshot"], "legacySnapshot must not be persisted in V2")
    }

    // MARK: - Multi-session isolation

    func testMultipleSessionsIndependent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = UnderstandingStoreV2(directory: dir)
        let a = UnderstandingArtifact(value: "a", source: .ai, trigger: .manualGenerate)
        let b = UnderstandingArtifact(value: "b", source: .ai, trigger: .manualGenerate)
        store.appendArtifact(for: "s1", field: .title, a)
        store.appendArtifact(for: "s2", field: .title, b)
        XCTAssertEqual(store.state(for: "s1")?.titleVersions.first?.value, "a")
        XCTAssertEqual(store.state(for: "s2")?.titleVersions.first?.value, "b")
        XCTAssertNil(store.state(for: "s3"))
    }
}
