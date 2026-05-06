import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// C2 coverage: pure humanizer
/// `UnderstandingDisplayPolicy.explanation(for:lastActiveAt:generatedAt:)`.
/// Per rev.3 humanizer mapping table.
final class StaleStateExplanationTests: XCTestCase {

    private let policy = UnderstandingDisplayPolicy()

    func testFreshExplanationIsNil() {
        let result = policy.explanation(
            for: .fresh,
            lastActiveAt: Date(),
            generatedAt: Date()
        )
        XCTAssertNil(result, ".fresh has no explanation text")
    }

    func testStaleSessionUpdatedRendersHourCount() {
        let generated = Date(timeIntervalSince1970: 0)
        let lastActive = Date(timeIntervalSince1970: 5 * 3600)
        let result = policy.explanation(
            for: .staleSessionUpdated(at: lastActive),
            lastActiveAt: lastActive,
            generatedAt: generated
        )
        XCTAssertEqual(result, "会话在生成后又更新了 5 小时,此字段可能不再可信")
    }

    func testStaleSessionUpdatedSubHourClampedToOne() {
        // 10-minute drift still renders ≥ 1 hour so the row never says
        // "更新了 0 小时".
        let generated = Date(timeIntervalSince1970: 0)
        let lastActive = Date(timeIntervalSince1970: 600)
        let result = policy.explanation(
            for: .staleSessionUpdated(at: lastActive),
            lastActiveAt: lastActive,
            generatedAt: generated
        )
        XCTAssertEqual(result, "会话在生成后又更新了 1 小时,此字段可能不再可信")
    }

    func testStaleSessionUpdatedTruncatesPartialHour() {
        // 5h59m → still 5 hours (floor truncation, not rounding).
        let generated = Date(timeIntervalSince1970: 0)
        let lastActive = Date(timeIntervalSince1970: 5 * 3600 + 3540)
        let result = policy.explanation(
            for: .staleSessionUpdated(at: lastActive),
            lastActiveAt: lastActive,
            generatedAt: generated
        )
        XCTAssertEqual(result, "会话在生成后又更新了 5 小时,此字段可能不再可信")
    }

    func testStalePartialEmbedsReason() {
        let result = policy.explanation(
            for: .stalePartial(reason: "title edited"),
            lastActiveAt: Date(),
            generatedAt: Date()
        )
        XCTAssertEqual(result, "此字段标注为 stale: title edited")
    }

    func testStalePartialEmptyReason() {
        let result = policy.explanation(
            for: .stalePartial(reason: ""),
            lastActiveAt: Date(),
            generatedAt: Date()
        )
        XCTAssertEqual(result, "此字段标注为 stale: ")
    }

    func testLegacyUnknownReturnsBaselineNotice() {
        let result = policy.explanation(
            for: .legacyUnknown,
            lastActiveAt: Date(),
            generatedAt: Date()
        )
        XCTAssertEqual(result, "Pre-v0.2.9 旧基线,无法判断时效")
    }
}
