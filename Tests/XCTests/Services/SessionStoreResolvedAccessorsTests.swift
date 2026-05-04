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

    // MARK: - resolvedMetadata source-awareness (regression)

    /// Legacy-only sessions live in V1 too (V1 is the legacy file). Without
    /// source-awareness, `understandingStore.snapshot(for:)` would fire
    /// first and surface the V1 stale signal — contradicting
    /// `StaleState.legacyUnknown`. This regression test enforces that a
    /// session whose every resolved field is `.legacy` reports
    /// `isStale = false` regardless of how old the V1 record is.
    func testLegacyOnlyMetadataNeverStale() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Pre-populate V1 with a snapshot whose basedOnLastActiveAt is
        // far in the past — V1 isStale comparison would return true.
        let writer = UnderstandingStore(directory: dir)
        let oldDate = Date(timeIntervalSinceNow: -86_400)
        writer.setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy title",
            progress: nil,
            summary: nil,
            modelName: "old-model",
            generatedAt: oldDate,
            basedOnLastActiveAt: oldDate
        ))

        let store = makeStore(directory: dir)
        // Confirm prerequisites: every resolved source is .legacy / non-V2.
        XCTAssertEqual(store.resolvedTitle(for: ref()).source, .legacy)
        // V1 stale check would itself say "stale" — guard against the bug:
        XCTAssertTrue(
            store.understandingStore.isStale(
                for: "s1", lastActiveAt: Date()
            ),
            "V1 isStale must say true for the bug surface; the source-aware "
            + "metadata accessor must overrule it"
        )

        let meta = store.resolvedMetadata(for: ref())
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.model, "old-model")
        XCTAssertEqual(
            meta?.isStale, false,
            "legacy-only session must never claim 已过期 (legacyUnknown semantics)"
        )
    }

    /// V2-active sessions still go through the V1 snapshot path so the
    /// existing `basedOnLastActiveAt`-based stale signal continues to
    /// work, including the 已过期 marker users already rely on.
    func testV2ActiveMetadataPropagatesV1Stale() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = makeStore(directory: dir)
        // Dual-write enhance with a snapshot that's old relative to "now".
        let oldSnap = LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "ai title",
            progress: nil,
            summary: "ai summary",
            modelName: "gpt-4o",
            generatedAt: Date(timeIntervalSinceNow: -3_600),
            basedOnLastActiveAt: Date(timeIntervalSinceNow: -3_600)
        )
        store.persistEnhancement(oldSnap)

        // Resolved sources should be .ai (dual-write created V2 artifacts).
        XCTAssertEqual(store.resolvedTitle(for: ref()).source, .ai)
        XCTAssertEqual(store.resolvedSummary(for: ref()).source, .ai)

        let meta = store.resolvedMetadata(for: ref())
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.model, "gpt-4o")
        XCTAssertEqual(
            meta?.isStale, true,
            "V2-active session with old snapshot must propagate V1 stale signal"
        )
    }

    /// No content at all (no V1 snapshot, no V2 artifacts, no legacy)
    /// → metadata is nil so the panel hides the model/time row.
    func testNoContentMetadataIsNil() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        XCTAssertNil(store.resolvedMetadata(for: ref()))
    }

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
