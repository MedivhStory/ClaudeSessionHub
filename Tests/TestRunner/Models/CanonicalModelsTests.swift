@testable import ClaudeSessionHubLib

enum CanonicalModelsTests {
    static func run() {
        print("── CanonicalModelsTests ──")
        testSessionRefEquality()
        testContextUsagePercentage()
        testContextUsageZeroLimit()
        testTokenBreakdownTotal()
        testModelInfoResolveOpus()
        testModelInfoResolveSonnet()
        testModelInfoResolveUnknown()
        testHealthSignalPriority()
    }

    static func testSessionRefEquality() {
        let a = SessionRef(providerID: "claude", sessionID: "abc")
        let b = SessionRef(providerID: "claude", sessionID: "abc")
        let c = SessionRef(providerID: "codex", sessionID: "abc")
        assertEqual(a, b, "same refs should be equal")
        check(a != c, "different provider refs should not be equal")
    }

    static func testContextUsagePercentage() {
        let usage = ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 749_897, limit: 1_000_000)
        assertEqual(usage.promptContext, 750_000, "promptContext should sum all token fields")
        assertApprox(usage.percentage, 0.75)
    }

    static func testContextUsageZeroLimit() {
        let usage = ContextUsage(inputTokens: 100, cacheCreationTokens: 0, cacheReadTokens: 0, limit: 0)
        assertApprox(usage.percentage, 0)
    }

    static func testTokenBreakdownTotal() {
        let t = TokenBreakdown(inputTokens: 100, outputTokens: 200, cacheReadTokens: 50, cacheWriteTokens: 30)
        assertEqual(t.totalTokens, 380)
    }

    static func testModelInfoResolveOpus() {
        let info = ModelInfo.resolve(modelName: "claude-opus-4-6")
        assertEqual(info.contextLimit, 1_000_000)
    }

    static func testModelInfoResolveSonnet() {
        let info = ModelInfo.resolve(modelName: "claude-sonnet-4-6")
        assertEqual(info.contextLimit, 200_000)
    }

    static func testModelInfoResolveUnknown() {
        let info = ModelInfo.resolve(modelName: nil)
        assertEqual(info.contextLimit, 200_000)
    }

    static func testHealthSignalPriority() {
        let stale = HealthSignal.stale(days: 3)
        let ctx = HealthSignal.contextNearFull(percentage: 0.82, used: 820_000, limit: 1_000_000)
        let err = HealthSignal.recentErrors(count: 2)
        check(stale.priority < ctx.priority, "stale should have higher priority than context")
        check(ctx.priority < err.priority, "context should have higher priority than errors")
    }
}
