import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class CanonicalModelsTests: XCTestCase {
    func testSessionRefEquality() {
        let a = SessionRef(providerID: "claude", sessionID: "abc")
        let b = SessionRef(providerID: "claude", sessionID: "abc")
        let c = SessionRef(providerID: "codex", sessionID: "abc")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testContextUsagePercentage() {
        let usage = ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 749_897, limit: 1_000_000)
        XCTAssertEqual(usage.promptContext, 750_000)
        XCTAssertEqual(usage.percentage, 0.75, accuracy: 0.001)
    }

    func testContextUsageZeroLimit() {
        let usage = ContextUsage(inputTokens: 100, cacheCreationTokens: 0, cacheReadTokens: 0, limit: 0)
        XCTAssertEqual(usage.percentage, 0)
    }

    func testTokenBreakdownTotal() {
        let t = TokenBreakdown(inputTokens: 100, outputTokens: 200, cacheReadTokens: 50, cacheWriteTokens: 30)
        XCTAssertEqual(t.totalTokens, 380)
    }

    func testModelInfoResolveOpus() {
        let info = ModelInfo.resolve(modelName: "claude-opus-4-6")
        XCTAssertEqual(info.contextLimit, 1_000_000)
    }

    func testModelInfoResolveSonnet() {
        let info = ModelInfo.resolve(modelName: "claude-sonnet-4-6")
        XCTAssertEqual(info.contextLimit, 200_000)
    }

    func testModelInfoResolveUnknown() {
        let info = ModelInfo.resolve(modelName: nil)
        XCTAssertEqual(info.contextLimit, 200_000)
    }

    func testHealthSignalPriority() {
        let stale = HealthSignal.stale(days: 3)
        let ctx = HealthSignal.contextNearFull(percentage: 0.82, used: 820_000, limit: 1_000_000)
        let err = HealthSignal.recentErrors(count: 2)
        XCTAssertLessThan(stale.priority, ctx.priority)
        XCTAssertLessThan(ctx.priority, err.priority)
    }
}
