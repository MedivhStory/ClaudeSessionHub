import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// C1 coverage: `SessionStore.fieldHistory(for:field:)` interleaves
/// V2 artifacts, selection events, and an optional legacy baseline row
/// chronologically, with `isCurrent` delegated to the display policy.
@MainActor
final class SessionStoreFieldHistoryTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-fieldhistory-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func makeStore(directory: String) -> SessionStore {
        SessionStore(
            coordinator: ScanCoordinator(providers: []),
            settings: SettingsStore(directory: directory, secretStore: InMemorySecretStore()),
            understandingStore: UnderstandingStore(directory: directory),
            understandingV2: UnderstandingStoreV2(directory: directory),
            legacyAdapter: LegacyUnderstandingAdapter(directory: directory)
        )
    }

    private func ref(_ sid: String = "s1") -> SessionRef {
        SessionRef(providerID: "claude", sessionID: sid)
    }

    private func writeLegacy(_ snap: LLMUnderstandingSnapshot, to directory: String) {
        UnderstandingStore(directory: directory).setSnapshot(snap)
    }

    private func writeRawV1JSON(_ raw: [String: [String: Any]], to directory: String) {
        let path = directory + "/understanding.json"
        let data = try! JSONSerialization.data(withJSONObject: raw)
        try! data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Empty state

    func testEmptySessionReturnsEmpty() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        XCTAssertEqual(store.fieldHistory(for: ref(), field: .title).count, 0)
        XCTAssertEqual(store.fieldHistory(for: ref(), field: .progress).count, 0)
        XCTAssertEqual(store.fieldHistory(for: ref(), field: .summary).count, 0)
    }

    // MARK: - Single artifact

    func testSingleAIArtifactIsCurrent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let art = UnderstandingArtifact(
            value: "ai title",
            source: .ai,
            trigger: .manualGenerate,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, art)

        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 1)
        guard case .artifact(let returned, let isCurrent) = history[0] else {
            return XCTFail("expected artifact entry")
        }
        XCTAssertEqual(returned.id, art.id)
        XCTAssertTrue(isCurrent, "lone AI artifact should be the current pointer")
    }

    // MARK: - Interleaving

    func testArtifactsAndSelectionsInterleavedChronologically() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)

        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)
        let t4 = Date(timeIntervalSince1970: 4000)

        let manual = UnderstandingArtifact(value: "manual", source: .manual, trigger: .manualEdit, createdAt: t1)
        let ai = UnderstandingArtifact(value: "ai", source: .ai, trigger: .manualGenerate, createdAt: t2)
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)

        let event = SelectionEvent(
            field: .title,
            action: .adopt,
            previousVersionID: manual.id,
            targetVersionID: ai.id,
            timestamp: t3
        )
        store.understandingV2.appendSelectionEvent(for: "s1", event)

        let manual2 = UnderstandingArtifact(value: "manual2", source: .manual, trigger: .manualEdit, createdAt: t4)
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual2)

        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(history[0].timestamp, t1)
        XCTAssertEqual(history[1].timestamp, t2)
        XCTAssertEqual(history[2].timestamp, t3)
        XCTAssertEqual(history[3].timestamp, t4)

        // manual2 is the current pointer (latest manual append always moves pointer).
        guard case .artifact(let lastArt, let lastIsCurrent) = history[3] else {
            return XCTFail("expected artifact at index 3")
        }
        XCTAssertEqual(lastArt.id, manual2.id)
        XCTAssertTrue(lastIsCurrent)

        // Earlier entries are not current.
        guard case .artifact(_, let firstIsCurrent) = history[0] else {
            return XCTFail()
        }
        XCTAssertFalse(firstIsCurrent)

        // Selection event has no isCurrent — just confirm shape.
        guard case .selection(let recordedEvent) = history[2] else {
            return XCTFail("expected selection at index 2")
        }
        XCTAssertEqual(recordedEvent.id, event.id)
    }

    // MARK: - Manual current with unadopted AI candidate

    func testManualCurrentMarksAICandidateNotCurrent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let manual = UnderstandingArtifact(
            value: "m",
            source: .manual,
            trigger: .manualEdit,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let ai = UnderstandingArtifact(
            value: "ai candidate",
            source: .ai,
            trigger: .manualGenerate,
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)

        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 2)
        guard case .artifact(let firstArt, let firstIsCurrent) = history[0],
              case .artifact(let secondArt, let secondIsCurrent) = history[1]
        else { return XCTFail("expected two artifact entries") }
        XCTAssertEqual(firstArt.id, manual.id)
        XCTAssertTrue(firstIsCurrent, "manual remains the current pointer after AI candidate is appended")
        XCTAssertEqual(secondArt.id, ai.id)
        XCTAssertFalse(secondIsCurrent, "AI candidate is appended without moving pointer")
    }

    // MARK: - Field-scoped selection events

    func testSelectionEventsFromOtherFieldsExcluded() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)

        let t = UnderstandingArtifact(
            value: "t",
            source: .ai,
            trigger: .manualGenerate,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, t)

        // Selection event on progress, NOT title.
        let progressEvent = SelectionEvent(
            field: .progress,
            action: .adopt,
            previousVersionID: nil,
            targetVersionID: UUID(),
            timestamp: Date(timeIntervalSince1970: 2000)
        )
        store.understandingV2.appendSelectionEvent(for: "s1", progressEvent)

        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 1, "title history must not include progress selection event")
    }

    // MARK: - Legacy

    func testLegacyOnlySessionShowsLegacyAsCurrent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeLegacy(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy title",
            progress: nil,
            summary: nil,
            modelName: "old-model",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ), to: dir)

        let store = makeStore(directory: dir)
        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 1)
        guard case .legacy(let snap, let field, let isCurrent) = history[0] else {
            return XCTFail("expected legacy entry")
        }
        XCTAssertEqual(snap.title, "legacy title")
        XCTAssertEqual(field, .title)
        XCTAssertTrue(isCurrent, "legacy is current when V2 has no artifact for this field")
    }

    func testLegacyNotCurrentWhenV2HasArtifact() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeLegacy(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy title",
            progress: nil,
            summary: nil,
            modelName: "m",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ), to: dir)

        let store = makeStore(directory: dir)
        let manual = UnderstandingArtifact(
            value: "v2 manual",
            source: .manual,
            trigger: .manualEdit,
            createdAt: Date(timeIntervalSince1970: 5000)
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)

        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 2)
        guard case .legacy(_, _, let legacyIsCurrent) = history[0] else {
            return XCTFail("expected legacy as oldest entry")
        }
        XCTAssertFalse(legacyIsCurrent, "V2 manual takes ownership; legacy is not current")
        guard case .artifact(_, let artifactIsCurrent) = history[1] else {
            return XCTFail("expected V2 artifact as newer entry")
        }
        XCTAssertTrue(artifactIsCurrent)
    }

    func testLegacyAbsentForFieldsWithoutValue() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        writeLegacy(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy title",
            progress: nil,
            summary: nil,
            modelName: "m",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ), to: dir)

        let store = makeStore(directory: dir)
        XCTAssertEqual(store.fieldHistory(for: ref(), field: .title).count, 1)
        XCTAssertEqual(
            store.fieldHistory(for: ref(), field: .progress).count, 0,
            "progress legacy entry must not appear when legacy.progress is nil"
        )
        XCTAssertEqual(
            store.fieldHistory(for: ref(), field: .summary).count, 0,
            "summary legacy entry must not appear when legacy.summary is nil"
        )
    }

    func testLegacyWithNilGeneratedAtSortsAtStart() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        // Write legacy via raw JSON because LLMUnderstandingSnapshot
        // requires a non-nil generatedAt; we want to exercise the
        // .distantPast fallback path on `HistoryEntry.timestamp`.
        writeRawV1JSON(["s1": ["title": "legacy"]], to: dir)

        let store = makeStore(directory: dir)
        let v2art = UnderstandingArtifact(
            value: "v2",
            source: .ai,
            trigger: .manualGenerate,
            createdAt: Date(timeIntervalSince1970: 5000)
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, v2art)

        let history = store.fieldHistory(for: ref(), field: .title)
        XCTAssertEqual(history.count, 2)
        guard case .legacy = history[0] else {
            return XCTFail("legacy with nil generatedAt must sort first")
        }
        guard case .artifact = history[1] else {
            return XCTFail("V2 artifact must sort after legacy with nil generatedAt")
        }
    }
}
