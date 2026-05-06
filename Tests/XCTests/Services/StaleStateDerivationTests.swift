import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// C2 coverage: pure derivation rules for
/// `UnderstandingDisplayPolicy.staleStateBy(...)`.
///
/// Rule order (rev.3):
/// 1. Legacy first → `.legacyUnknown`
/// 2. Stored `.stalePartial(reason)` preserved
/// 3. Stored `.fresh` + session drift → `.staleSessionUpdated(at:)`
/// 4. Else → `.fresh`
final class StaleStateDerivationTests: XCTestCase {

    private let policy = UnderstandingDisplayPolicy()

    // MARK: - Rule 1: Legacy first

    func testLegacyAlwaysLegacyUnknownEvenWithOldGeneratedAt() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 1_000_000)
        let result = policy.staleStateBy(
            resolvedSource: .legacy,
            storedStale: .legacyUnknown,
            artifactCreatedAt: oldDate,
            sessionLastActiveAt: newDate
        )
        XCTAssertEqual(result, .legacyUnknown)
    }

    func testLegacySourceOverridesStoredPartial() {
        let result = policy.staleStateBy(
            resolvedSource: .legacy,
            storedStale: .stalePartial(reason: "x"),
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(
            result, .legacyUnknown,
            "legacy source must rank ahead of stored partial"
        )
    }

    // MARK: - Rule 2: Stored partial preserved

    func testStoredPartialStaleNotOverriddenByDerivation() {
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .stalePartial(reason: "title edited"),
            artifactCreatedAt: Date(timeIntervalSince1970: 100),
            sessionLastActiveAt: Date(timeIntervalSince1970: 1_000_000)
        )
        XCTAssertEqual(
            result, .stalePartial(reason: "title edited"),
            "session drift must not displace a stored .stalePartial reason"
        )
    }

    func testStoredPartialPreservedRegardlessOfManualSource() {
        let result = policy.staleStateBy(
            resolvedSource: .manual,
            storedStale: .stalePartial(reason: "edited"),
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(result, .stalePartial(reason: "edited"))
    }

    // MARK: - Rule 3: Session drift

    func testSessionUpdatedAfterArtifactDerivesStale() {
        let createdAt = Date(timeIntervalSince1970: 1000)
        let lastActive = Date(timeIntervalSince1970: 2000)
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: createdAt,
            sessionLastActiveAt: lastActive
        )
        XCTAssertEqual(result, .staleSessionUpdated(at: lastActive))
    }

    func testSessionNotUpdatedAfterArtifactStaysFresh() {
        let createdAt = Date(timeIntervalSince1970: 2000)
        let lastActive = Date(timeIntervalSince1970: 1000)
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: createdAt,
            sessionLastActiveAt: lastActive
        )
        XCTAssertEqual(result, .fresh)
    }

    func testEqualTimestampsIsFresh() {
        let when = Date(timeIntervalSince1970: 1000)
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: when,
            sessionLastActiveAt: when
        )
        XCTAssertEqual(
            result, .fresh,
            "drift requires lastActive STRICTLY greater than createdAt"
        )
    }

    // MARK: - Rule 4: fallback

    func testNilTimestampsReturnFresh() {
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .fresh,
            artifactCreatedAt: nil,
            sessionLastActiveAt: nil
        )
        XCTAssertEqual(result, .fresh)
    }

    func testNilStoredStaleReturnsFresh() {
        // Rule/uuid/none sources have nil staleState; derivation must
        // fall through to .fresh.
        let result = policy.staleStateBy(
            resolvedSource: .rule,
            storedStale: nil,
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(result, .fresh)
    }

    func testStoredStaleSessionUpdatedNotPreserved() {
        // Spec: derivation only fires when stored is .fresh. A stored
        // .staleSessionUpdated falls through rule 3's preconditions and
        // ends at rule 4 → .fresh. Drift is recomputed at read time, not
        // trusted from storage.
        let result = policy.staleStateBy(
            resolvedSource: .ai,
            storedStale: .staleSessionUpdated(at: Date()),
            artifactCreatedAt: Date(),
            sessionLastActiveAt: Date()
        )
        XCTAssertEqual(result, .fresh)
    }
}

// MARK: - SessionStore wiring

/// C2 wiring coverage: `SessionStore.resolvedStaleState(for:field:)`
/// composes `resolved*` + chain artifact lookup + `staleStateBy(...)`.
@MainActor
final class SessionStoreResolvedStaleStateTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "csh-stale-\(UUID().uuidString)"
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

    /// With no V2 state and no legacy, all fields resolve to rule/uuid/none
    /// sources; derivation falls through to `.fresh`.
    func testEmptyResolvesFresh() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .title), .fresh)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .progress), .fresh)
        XCTAssertEqual(store.resolvedStaleState(for: ref(), field: .summary), .fresh)
    }

    /// Legacy-only session: rule 1 fires regardless of artifact dates.
    func testLegacyOnlyReturnsLegacyUnknown() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        UnderstandingStore(directory: dir).setSnapshot(LLMUnderstandingSnapshot(
            sessionID: "s1",
            title: "legacy",
            progress: nil,
            summary: nil,
            modelName: "m",
            generatedAt: Date(timeIntervalSince1970: 100),
            basedOnLastActiveAt: Date()
        ))
        let store = makeStore(directory: dir)
        XCTAssertEqual(
            store.resolvedStaleState(for: ref(), field: .title),
            .legacyUnknown
        )
    }

    /// Stored partial on a V2 manual artifact survives derivation.
    func testStoredPartialPreservedThroughSessionStore() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let store = makeStore(directory: dir)
        let artifact = UnderstandingArtifact(
            value: "manual edited",
            source: .manual,
            trigger: .manualEdit,
            createdAt: Date(timeIntervalSince1970: 1000),
            staleState: .stalePartial(reason: "user-edited")
        )
        store.understandingV2.appendArtifact(for: "s1", field: .title, artifact)
        XCTAssertEqual(
            store.resolvedStaleState(for: ref(), field: .title),
            .stalePartial(reason: "user-edited")
        )
    }
}
