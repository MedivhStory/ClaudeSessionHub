import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// Coverage for `SessionStore.resolvedTitle/Progress/Summary` — the seam
/// views consume in v0.2.9 P1.
@MainActor
final class SessionStoreResolvedAccessorsTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-resolved-\(UUID().uuidString)"
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

    private func snapshot(
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

    // MARK: - resolvedTitle

    func testResolvedTitleEmptyFallsToUUIDPrefix() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let r = store.resolvedTitle(for: ref("abcdefghij"))
        XCTAssertEqual(r.source, .uuidPrefix)
        XCTAssertEqual(r.value, "abcdefgh")
    }

    func testResolvedTitleLegacyVisible() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        // Pre-populate V1
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(snapshot(title: "legacy title"))

        let store = makeStore(directory: dir)
        let r = store.resolvedTitle(for: ref())
        XCTAssertEqual(r.source, .legacy)
        XCTAssertEqual(r.value, "legacy title")
        XCTAssertEqual(r.staleState, .legacyUnknown)
    }

    func testResolvedTitleAIWinsAfterDualWrite() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        // Start with legacy.
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(snapshot(title: "legacy title"))

        let store = makeStore(directory: dir)
        // Trigger dual-write enhance.
        store.persistEnhancement(snapshot(title: "ai title"))

        let r = store.resolvedTitle(for: ref())
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai title")
        // Legacy chip must no longer own this field after AI regenerate.
        XCTAssertNotEqual(r.source, .legacy)
    }

    // MARK: - resolvedProgress

    func testResolvedProgressLegacyOnly() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(snapshot(progress: "legacy prog"))
        let store = makeStore(directory: dir)
        let r = store.resolvedProgress(for: ref())
        XCTAssertEqual(r.source, .legacy)
        XCTAssertEqual(r.value, "legacy prog")
    }

    func testResolvedProgressNoneWhenNothingExists() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let r = store.resolvedProgress(for: ref())
        XCTAssertEqual(r.source, .none)
        XCTAssertNil(r.value)
    }

    // MARK: - resolvedSummary

    func testResolvedSummaryAIOverLegacyAfterDualWrite() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(snapshot(summary: "legacy summary"))
        let store = makeStore(directory: dir)
        store.persistEnhancement(snapshot(summary: "ai summary"))
        let r = store.resolvedSummary(for: ref())
        XCTAssertEqual(r.source, .ai)
        XCTAssertEqual(r.value, "ai summary")
    }

    func testResolvedSummaryNoneWhenLegacyHasNoSummary() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        // Hand-write V1 with title only — no summary
        let path = dir + "/understanding.json"
        let dict: [String: Any] = ["s1": ["title": "x"]]
        try! JSONSerialization.data(withJSONObject: dict)
            .write(to: URL(fileURLWithPath: path))

        let store = makeStore(directory: dir)
        let r = store.resolvedSummary(for: ref())
        XCTAssertEqual(r.source, .none)
        XCTAssertNil(r.value)
    }

    // MARK: - Cross-field after regenerate

    /// Verifies the spec promise: after AI regenerate creates V2 artifacts,
    /// the legacy chip should disappear for those fields and AI chip should show.
    func testRegenerateReplacesLegacyChipAcrossFields() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let writer = UnderstandingStore(directory: dir)
        writer.setSnapshot(snapshot(
            title: "legacy title",
            progress: "legacy progress",
            summary: "legacy summary"
        ))

        let store = makeStore(directory: dir)
        // Before regenerate: all three fields should be .legacy
        XCTAssertEqual(store.resolvedTitle(for: ref()).source, .legacy)
        XCTAssertEqual(store.resolvedProgress(for: ref()).source, .legacy)
        XCTAssertEqual(store.resolvedSummary(for: ref()).source, .legacy)

        store.persistEnhancement(snapshot(
            title: "ai title",
            progress: "ai progress",
            summary: "ai summary"
        ))

        // After regenerate: all three fields should be .ai
        XCTAssertEqual(store.resolvedTitle(for: ref()).source, .ai)
        XCTAssertEqual(store.resolvedProgress(for: ref()).source, .ai)
        XCTAssertEqual(store.resolvedSummary(for: ref()).source, .ai)
    }
}
