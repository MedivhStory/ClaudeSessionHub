import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class SessionSignalsTests: XCTestCase {

    func testSessionSignalsDefaults() {
        let signals = SessionSignals(sessionID: "test-123")
        XCTAssertEqual(signals.sessionID, "test-123")
        XCTAssertNil(signals.firstUserIntent)
        XCTAssertNil(signals.lastUserIntent)
        XCTAssertNil(signals.lastAssistantProgress)
        XCTAssertEqual(signals.historyDisplayTexts, [])
        XCTAssertNil(signals.taskSubject)
        XCTAssertNil(signals.taskStatus)
        XCTAssertNil(signals.entrypoint)
        XCTAssertNil(signals.branch)
        XCTAssertEqual(signals.toolsUsed, [])
        XCTAssertFalse(signals.isSidechain)
    }

    func testGeneratedTitleSource() {
        let title = GeneratedTitle(
            text: "重构 auth middleware",
            source: .rule,
            generatedAt: Date()
        )
        XCTAssertEqual(title.source, .rule)
        XCTAssertEqual(title.text, "重构 auth middleware")
    }

    func testTitleHistoryAppend() {
        var history = TitleHistory(sessionID: "s1")
        let t1 = GeneratedTitle(text: "初始标题", source: .rule, generatedAt: Date())
        history.append(t1)
        XCTAssertEqual(history.entries.count, 1)

        let t2 = GeneratedTitle(text: "演化标题", source: .rule, generatedAt: Date())
        history.append(t2)
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.current?.text, "演化标题")
    }
}
