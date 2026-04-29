import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// Migration scenarios for the v0.2.9 hybrid model:
/// `understanding.json` (V1, read-only legacy) coexists with
/// `understanding-v2.json` (V2, new authoritative). AI enhance dual-writes
/// both. Display policy resolves precedence across sources.
@MainActor
final class UnderstandingMigrationTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-migration-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func mtime(of path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
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

    private func makeSnapshot(
        sessionID: String = "s1",
        title: String = "ai title",
        progress: String? = "ai progress",
        summary: String? = "ai summary"
    ) -> LLMUnderstandingSnapshot {
        LLMUnderstandingSnapshot(
            sessionID: sessionID,
            title: title,
            progress: progress,
            summary: summary,
            modelName: "gpt-4o",
            generatedAt: Date(),
            basedOnLastActiveAt: Date()
        )
    }

    // MARK: - V1 exists, V2 absent

    func testV1ExistsV2AbsentLegacyVisibleViaAdapter() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Pre-populate V1 via the production V1 writer.
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "v1 title",
            progress: "v1 progress",
            summary: "v1 summary",
            modelName: "v1-model",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            basedOnLastActiveAt: Date()
        ))

        let v2Path = dir + "/understanding-v2.json"
        XCTAssertFalse(FileManager.default.fileExists(atPath: v2Path),
                       "V2 file must not exist before any AI enhance happens")

        let store = makeStore(directory: dir)
        // Legacy must be readable through the adapter.
        let legacy = store.legacyAdapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "v1 title")
        XCTAssertEqual(legacy?.progress, "v1 progress")
        XCTAssertEqual(legacy?.summary, "v1 summary")
        XCTAssertEqual(legacy?.modelName, "v1-model")

        // Display policy resolves to legacy because no V2 state exists.
        let title = store.displayPolicy.resolveTitle(
            state: store.understandingV2.state(for: "s1"),
            legacy: legacy,
            ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(title.value, "v1 title")
        XCTAssertEqual(title.source, .legacy)
        XCTAssertEqual(title.staleState, .legacyUnknown)
    }

    func testV1MtimeUnchangedOnAppInitAndReadOnlyAccess() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Pre-populate V1.
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(makeSnapshot())

        let v1Path = dir + "/understanding.json"
        // Force mtime to a known past instant so any write would be detectable.
        let pastDate = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: v1Path
        )
        let mtimeBefore = mtime(of: v1Path)!

        // Construct SessionStore — should not write to V1.
        let store = makeStore(directory: dir)

        // Multiple read-only accesses through the legacy adapter.
        _ = store.legacyAdapter.legacySnapshot(for: "s1")
        _ = store.legacyAdapter.legacySnapshot(for: "ghost")
        _ = store.understandingV2.state(for: "s1")

        let mtimeAfter = mtime(of: v1Path)!
        XCTAssertEqual(
            mtimeBefore,
            mtimeAfter,
            "understanding.json mtime must not change on app init or read-only access"
        )
    }

    func testV1MtimeChangesAfterDualWriteEnhance() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Pre-populate V1.
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(makeSnapshot())

        let v1Path = dir + "/understanding.json"
        let pastDate = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: v1Path
        )
        let mtimeBefore = mtime(of: v1Path)!

        let store = makeStore(directory: dir)
        // Trigger the dual-write path with a fresh snapshot.
        store.persistEnhancement(makeSnapshot(title: "new title"))

        let mtimeAfter = mtime(of: v1Path)!
        XCTAssertGreaterThan(
            mtimeAfter,
            mtimeBefore,
            "understanding.json mtime must advance after dual-write enhance"
        )
    }

    func testDualWriteCreatesV2FileOnFirstEnhance() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Pre-populate V1 only.
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(makeSnapshot(sessionID: "old-session"))

        let v2Path = dir + "/understanding-v2.json"
        XCTAssertFalse(FileManager.default.fileExists(atPath: v2Path))

        let store = makeStore(directory: dir)
        store.persistEnhancement(makeSnapshot(sessionID: "s1"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: v2Path),
                      "V2 file must be created on first enhance")

        let state = store.understandingV2.state(for: "s1")
        XCTAssertEqual(state?.titleVersions.count, 1)
        XCTAssertEqual(state?.progressVersions.count, 1)
        XCTAssertEqual(state?.summaryVersions.count, 1)
        XCTAssertNotNil(state?.currentTitleVersionID)
        XCTAssertNotNil(state?.currentProgressVersionID)
        XCTAssertNotNil(state?.currentSummaryVersionID)
    }

    // MARK: - V1 exists, V2 exists (same session)

    /// Construct the V1/V2 split directly (without dual-write) to verify
    /// the precedence rule in isolation. Real production dual-write
    /// updates both files in lockstep — that case is covered by
    /// `testDualWriteSameSessionUpdatesBothFiles` below.
    func testSameSessionV2WinsOverLegacyViaPolicy() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(makeSnapshot(title: "v1 title"))

        let store = makeStore(directory: dir)
        // Direct V2 append (no dual-write) so V1 keeps "v1 title".
        let ai = UnderstandingArtifact(
            value: "v2 title",
            source: .ai,
            trigger: .manualGenerate
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)

        let legacy = store.legacyAdapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "v1 title",
                       "legacy reads from V1 file, which was not touched here")

        let resolved = store.displayPolicy.resolveTitle(
            state: store.understandingV2.state(for: "s1"),
            legacy: legacy,
            ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(resolved.value, "v2 title")
        XCTAssertEqual(resolved.source, .ai)
    }

    /// Real dual-write behavior: AI enhance updates BOTH V1 and V2 for
    /// the same session. V1 stays current (downgrade safe), V2 carries
    /// the new versioned artifact, both files reflect new content.
    func testDualWriteSameSessionUpdatesBothFiles() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(makeSnapshot(title: "old v1 title"))

        let store = makeStore(directory: dir)
        store.persistEnhancement(makeSnapshot(title: "new ai title"))

        let legacy = store.legacyAdapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "new ai title",
                       "V1 dual-write keeps legacy file current after enhance")

        let state = store.understandingV2.state(for: "s1")
        XCTAssertEqual(state?.titleVersions.last?.value, "new ai title")
        XCTAssertEqual(state?.titleVersions.count, 1)
    }

    func testV1AndV2DifferentSessionsLegacyOnlyForV1Session() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(makeSnapshot(sessionID: "old", title: "legacy"))

        let store = makeStore(directory: dir)
        store.persistEnhancement(makeSnapshot(sessionID: "new", title: "v2"))

        // "old" only has legacy
        let oldResolved = store.displayPolicy.resolveTitle(
            state: store.understandingV2.state(for: "old"),
            legacy: store.legacyAdapter.legacySnapshot(for: "old"),
            ruleTitle: nil,
            sessionIDForFallback: "old"
        )
        XCTAssertEqual(oldResolved.source, .legacy)
        XCTAssertEqual(oldResolved.value, "legacy")

        // "new" has V2 only
        let newResolved = store.displayPolicy.resolveTitle(
            state: store.understandingV2.state(for: "new"),
            legacy: store.legacyAdapter.legacySnapshot(for: "new"),
            ruleTitle: nil,
            sessionIDForFallback: "new"
        )
        XCTAssertEqual(newResolved.source, .ai)
        XCTAssertEqual(newResolved.value, "v2")
    }

    // MARK: - V1 absent, V2 exists

    /// Construct V2-only state via direct V2 write so V1 file truly
    /// stays absent. Real dual-write would create both — that's covered
    /// by `testDualWriteCreatesV2FileOnFirstEnhance`.
    func testV1AbsentV2DirectWriteWorks() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = makeStore(directory: dir)
        let ai = UnderstandingArtifact(
            value: "v2 only",
            source: .ai,
            trigger: .manualGenerate
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, ai)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir + "/understanding.json"),
            "V1 file must not exist when only V2 store is written"
        )
        XCTAssertNil(store.legacyAdapter.legacySnapshot(for: "s1"))

        let resolved = store.displayPolicy.resolveTitle(
            state: store.understandingV2.state(for: "s1"),
            legacy: nil,
            ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(resolved.source, .ai)
        XCTAssertEqual(resolved.value, "v2 only")
    }

    // MARK: - Neither file

    func testNeitherFileFallsBackToRuleAndUUID() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = makeStore(directory: dir)
        // Nothing written; both files absent.
        XCTAssertNil(store.legacyAdapter.legacySnapshot(for: "ghost"))
        XCTAssertNil(store.understandingV2.state(for: "ghost"))

        let withRule = store.displayPolicy.resolveTitle(
            state: nil, legacy: nil, ruleTitle: "rule title",
            sessionIDForFallback: "ghost-session-id"
        )
        XCTAssertEqual(withRule.source, .rule)
        XCTAssertEqual(withRule.value, "rule title")

        let noRule = store.displayPolicy.resolveTitle(
            state: nil, legacy: nil, ruleTitle: nil,
            sessionIDForFallback: "abcdefghi"
        )
        XCTAssertEqual(noRule.source, .uuidPrefix)
        XCTAssertEqual(noRule.value, "abcdefgh")
    }

    // MARK: - Partial V1

    func testPartialV1TitleOnlyHandledByDisplayPolicy() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Hand-write a partial V1 record (title only).
        let path = dir + "/understanding.json"
        let dict: [String: Any] = ["s1": ["title": "title only"]]
        let data = try JSONSerialization.data(withJSONObject: dict)
        try data.write(to: URL(fileURLWithPath: path))

        let store = makeStore(directory: dir)
        let legacy = store.legacyAdapter.legacySnapshot(for: "s1")
        XCTAssertEqual(legacy?.title, "title only")
        XCTAssertNil(legacy?.progress)
        XCTAssertNil(legacy?.summary)

        let titleR = store.displayPolicy.resolveTitle(
            state: nil, legacy: legacy, ruleTitle: nil,
            sessionIDForFallback: "s1"
        )
        XCTAssertEqual(titleR.value, "title only")
        XCTAssertEqual(titleR.source, .legacy)

        // Progress falls through to .none (no rule fallback provided).
        let progressR = store.displayPolicy.resolveProgress(
            state: nil, legacy: legacy, ruleProgress: nil
        )
        XCTAssertEqual(progressR.source, .none)

        // Summary similarly.
        let summaryR = store.displayPolicy.resolveSummary(state: nil, legacy: legacy)
        XCTAssertEqual(summaryR.source, .none)
    }

    // MARK: - Dual-write content correctness

    func testDualWriteOmitsOptionalFieldsWhenNil() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = makeStore(directory: dir)
        // Snapshot with no progress, no summary.
        store.persistEnhancement(makeSnapshot(progress: nil, summary: nil))

        let state = store.understandingV2.state(for: "s1")
        XCTAssertEqual(state?.titleVersions.count, 1)
        XCTAssertEqual(state?.progressVersions.count, 0,
                       "no progress artifact should be written when snapshot.progress is nil")
        XCTAssertEqual(state?.summaryVersions.count, 0,
                       "no summary artifact should be written when snapshot.summary is nil")
    }

    func testDualWritePointerRulesPreserveManual() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = makeStore(directory: dir)
        // Step 1: simulate a manual edit by appending a manual artifact via V2 store directly.
        let manual = UnderstandingArtifact(
            value: "manual title",
            source: .manual,
            trigger: .manualEdit
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, manual)
        XCTAssertEqual(store.understandingV2.state(for: "s1")?.currentTitleVersionID, manual.id)

        // Step 2: AI enhance via dual-write — pointer must NOT move because
        // current is a manual artifact.
        store.persistEnhancement(makeSnapshot(title: "ai title"))

        let state = store.understandingV2.state(for: "s1")!
        XCTAssertEqual(state.titleVersions.count, 2)
        XCTAssertEqual(state.currentTitleVersionID, manual.id,
                       "AI dual-write must not displace the manual current pointer")
    }
}
