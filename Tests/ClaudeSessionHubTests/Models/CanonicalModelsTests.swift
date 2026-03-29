import Testing
@testable import ClaudeSessionHub

@Suite("Canonical Models")
struct CanonicalModelsTests {
    @Test func sessionRefEquality() {
        let a = SessionRef(providerID: "claude", sessionID: "abc")
        let b = SessionRef(providerID: "claude", sessionID: "abc")
        let c = SessionRef(providerID: "codex", sessionID: "abc")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func contextUsagePercentage() {
        let usage = ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 749_897, limit: 1_000_000)
        #expect(usage.promptContext == 750_000)
        #expect(abs(usage.percentage - 0.75) < 0.001)
    }

    @Test func contextUsageZeroLimit() {
        let usage = ContextUsage(inputTokens: 100, cacheCreationTokens: 0, cacheReadTokens: 0, limit: 0)
        #expect(usage.percentage == 0)
    }

    @Test func tokenBreakdownTotal() {
        let t = TokenBreakdown(inputTokens: 100, outputTokens: 200, cacheReadTokens: 50, cacheWriteTokens: 30)
        #expect(t.totalTokens == 380)
    }

    @Test func modelInfoResolveOpus() {
        let info = ModelInfo.resolve(modelName: "claude-opus-4-6")
        #expect(info.contextLimit == 1_000_000)
    }

    @Test func modelInfoResolveSonnet() {
        let info = ModelInfo.resolve(modelName: "claude-sonnet-4-6")
        #expect(info.contextLimit == 200_000)
    }

    @Test func modelInfoResolveUnknown() {
        let info = ModelInfo.resolve(modelName: nil)
        #expect(info.contextLimit == 200_000)
    }

    @Test func healthSignalPriority() {
        let stale = HealthSignal.stale(days: 3)
        let ctx = HealthSignal.contextNearFull(percentage: 0.82, used: 820_000, limit: 1_000_000)
        let err = HealthSignal.recentErrors(count: 2)
        #expect(stale.priority < ctx.priority)
        #expect(ctx.priority < err.priority)
    }
}
