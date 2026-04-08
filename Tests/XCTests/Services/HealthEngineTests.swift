import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class HealthEngineXCTests: XCTestCase {

    private func makeSession(runtimeState: RuntimeState, taskPhase: TaskPhase,
                             lastActiveAt: Date, recentErrorCount: Int,
                             contextUsage: ContextUsage?) -> SessionSummary {
        SessionSummary(
            ref: SessionRef(providerID: "claude", sessionID: "test"),
            title: "Test", currentTaskSummary: nil,
            runtimeState: runtimeState, taskPhase: taskPhase,
            cwd: nil, branch: nil, turnCount: 10, filesTouched: 3,
            recentErrorCount: recentErrorCount,
            createdAt: Date(), lastActiveAt: lastActiveAt,
            contextUsage: contextUsage
        )
    }

    func testHealthySessionNoSignals() {
        let summary = makeSession(runtimeState: .active, taskPhase: .inProgress,
                                  lastActiveAt: Date(), recentErrorCount: 0, contextUsage: nil)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertTrue(signals.isEmpty, "healthy session should have no signals")
    }

    func testStaleSessionTriggersWarning() {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600)
        let summary = makeSession(runtimeState: .stopped, taskPhase: .unknown,
                                  lastActiveAt: threeDaysAgo, recentErrorCount: 0, contextUsage: nil)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertEqual(signals.count, 1, "stale session should have 1 signal")
        if case .stale(let days) = signals.first {
            XCTAssertEqual(days, 3, "should be 3 days stale")
        } else {
            XCTFail("expected stale signal")
        }
    }

    func testDoneSessionNoStaleWarning() {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600)
        let summary = makeSession(runtimeState: .stopped, taskPhase: .done,
                                  lastActiveAt: threeDaysAgo, recentErrorCount: 0, contextUsage: nil)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertTrue(signals.isEmpty, "done session should not trigger stale")
    }

    func testContextNearFullSignal() {
        let usage = ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 799_897, limit: 1_000_000)
        let summary = makeSession(runtimeState: .stopped, taskPhase: .inProgress,
                                  lastActiveAt: Date(), recentErrorCount: 0, contextUsage: usage)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertTrue(signals.contains(where: { if case .contextNearFull = $0 { return true }; return false }),
                      "should have contextNearFull signal")
    }

    func testContextBelowThresholdNoSignal() {
        let usage = ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 50_000, limit: 1_000_000)
        let summary = makeSession(runtimeState: .active, taskPhase: .inProgress,
                                  lastActiveAt: Date(), recentErrorCount: 0, contextUsage: usage)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertTrue(signals.isEmpty, "context below 75% should have no signal")
    }

    func testRecentErrorsSignal() {
        let summary = makeSession(runtimeState: .active, taskPhase: .inProgress,
                                  lastActiveAt: Date(), recentErrorCount: 3, contextUsage: nil)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertEqual(signals.count, 1, "should have 1 error signal")
        if case .recentErrors(let count) = signals.first {
            XCTAssertEqual(count, 3, "should have 3 errors")
        } else {
            XCTFail("expected recentErrors signal")
        }
    }

    func testMaxTwoSignals() {
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 3600)
        let usage = ContextUsage(inputTokens: 3, cacheCreationTokens: 100, cacheReadTokens: 899_897, limit: 1_000_000)
        let summary = makeSession(runtimeState: .stopped, taskPhase: .unknown,
                                  lastActiveAt: fiveDaysAgo, recentErrorCount: 5, contextUsage: usage)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertEqual(signals.count, 2, "max 2 signals")
        if case .stale = signals[0] {} else { XCTFail("first should be stale") }
        if case .contextNearFull = signals[1] {} else { XCTFail("second should be contextNearFull") }
    }

    func testActiveSessionNotStale() {
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 3600)
        let summary = makeSession(runtimeState: .active, taskPhase: .inProgress,
                                  lastActiveAt: fiveDaysAgo, recentErrorCount: 0, contextUsage: nil)
        let signals = HealthEngine.computeSignals(for: summary)
        XCTAssertTrue(signals.isEmpty, "active session should never be stale regardless of lastActiveAt")
    }
}
