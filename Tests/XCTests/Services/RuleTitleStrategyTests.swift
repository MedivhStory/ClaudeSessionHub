import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class RuleTitleStrategyTests: XCTestCase {

    private let strategy = RuleTitleStrategy()

    // MARK: - Title Generation

    func testHistoryDisplayPreferred() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["帮我重构 auth middleware"]
        signals.firstUserIntent = "some longer message about refactoring"

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.contains("帮我重构"))
        XCTAssertEqual(result.source, .rule)
    }

    func testFallsBackToFirstUserIntent() {
        var signals = SessionSignals(sessionID: "s1")
        signals.firstUserIntent = "fix the login timeout bug"

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.contains("fix the login"))
        XCTAssertEqual(result.source, .rule)
    }

    func testTaskSubjectUsedWhenNoHistory() {
        var signals = SessionSignals(sessionID: "s1")
        signals.taskSubject = "Refactor auth to protocol-based"

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.contains("Refactor auth"))
    }

    func testSlugFallback() {
        var signals = SessionSignals(sessionID: "s1")
        signals.slug = "my-custom-slug"

        let result = strategy.generateTitle(from: signals)
        XCTAssertEqual(result.text, "my-custom-slug")
    }

    func testSessionIDUltimateFallback() {
        let signals = SessionSignals(sessionID: "abcd1234-5678")
        let result = strategy.generateTitle(from: signals)
        XCTAssertEqual(result.text, "abcd1234")
    }

    func testResumeEntrypointSkipsHistoryForTitle() {
        var signals = SessionSignals(sessionID: "s1")
        signals.entrypoint = "resume"
        signals.historyDisplayTexts = ["/resume"]
        signals.firstUserIntent = "continue the auth work"

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("/resume"))
    }

    func testTitleTruncation() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = [String(repeating: "很长的文本", count: 20)]

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.count <= 50)
    }

    // MARK: - Inline Pasted Wrapper Removal

    func testInlinePastedWrapperRemoved() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["你根据这个会议录音 [Pasted text #1 +192 lines] 梳理会议需求"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("[Pasted"))
        XCTAssertTrue(result.text.contains("会议"))
    }

    func testPrefixPastedWrapperRemoved() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["[Pasted text #2 +36 lines] 读完你就会发现，本质上是知识库"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("[Pasted"))
        XCTAssertTrue(result.text.contains("知识库"))
    }

    // MARK: - Multiline Collapse

    func testMultilineHistoryCollapsedToSingleLine() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["Fix Tailscale 登录失败\n\ntailscale\n\n\n\n\n我的tailscale 无法登陆 帮我看看"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("\n"))
        XCTAssertTrue(result.text.contains("Tailscale"))
    }

    // MARK: - Shell Command Demotion

    func testShellCommandNotDirectlyUsedAsTitle() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["npx skills add https://github.com/vercel-labs/skills --skill=foo"]
        signals.taskSubject = "Install Vercel skills"

        let result = strategy.generateTitle(from: signals)
        // Should prefer task subject over raw shell command
        XCTAssertTrue(result.text.contains("Install Vercel"))
        XCTAssertFalse(result.text.hasPrefix("npx"))
    }

    func testShellCommandWithChineseIntentExtractsIntent() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["npm install axios 帮我安装这个依赖"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.contains("帮我安装"))
        XCTAssertFalse(result.text.hasPrefix("npm"))
    }

    func testPureShellCommandFallsToNextCandidate() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["git push origin main"]
        signals.firstUserIntent = "推送代码到远程仓库"

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.contains("推送代码"))
    }

    // MARK: - Terminal Prompt Chars

    func testTerminalPromptCharsStripped() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["▎ 读这个 txt 版本"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("▎"))
        XCTAssertTrue(result.text.contains("读这个"))
    }

    // MARK: - File Path Stripping

    func testAbsolutePathStrippedFromTitle() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["读这个 txt 版本：/Users/medivh/Documents/OACP/讨论存档.txt"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("/Users/"))
        XCTAssertTrue(result.text.contains("读这个"))
    }

    func testShellEscapedPathStrippedCleanly() {
        // Real case: OACP\ ai\ team\ memory/讨论存档20260322.pages
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["/Users/medivh/Documents/OACP\\ ai\\ team\\ memory/讨论存档20260322.pages 这是一个产品构思讨论"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("/Users/"))
        XCTAssertFalse(result.text.contains("\\ "))
        XCTAssertFalse(result.text.contains("memory/"))
        XCTAssertTrue(result.text.contains("产品构思讨论"))
    }

    func testPathPrefixedHistoryEntryBecomesUsable() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["/Users/foo/bar.pages 这是一个产品构思讨论 请你阅读"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("/Users/"))
        XCTAssertTrue(result.text.contains("产品构思讨论"))
    }

    // MARK: - Last Progress

    func testLastProgressFromAssistant() {
        var signals = SessionSignals(sessionID: "s1")
        signals.lastAssistantProgress = "代码已修改完成。接下来需要运行测试确认所有功能正常。"

        let result = strategy.extractLastProgress(from: signals)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("代码已修改完成"))
    }

    func testLastProgressFromTaskStatus() {
        var signals = SessionSignals(sessionID: "s1")
        signals.taskSubject = "Add auth tests"
        signals.taskStatus = "completed"

        let result = strategy.extractLastProgress(from: signals)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Add auth tests"))
    }

    func testLastProgressNilWhenNoSignals() {
        let signals = SessionSignals(sessionID: "s1")
        let result = strategy.extractLastProgress(from: signals)
        XCTAssertNil(result)
    }

    func testLastProgressDoesNotFallbackToUserIntent() {
        var signals = SessionSignals(sessionID: "s1")
        signals.lastUserIntent = "刚停电了 恢复这个工作区"
        // No assistant progress, no task status

        let result = strategy.extractLastProgress(from: signals)
        XCTAssertNil(result, "lastProgress must not fallback to user intent")
    }

    // MARK: - First Generation Gate

    func testGatePassesWithProgressSignal() {
        var signals = SessionSignals(sessionID: "s1")
        signals.turnCount = 2
        signals.lastAssistantProgress = "Done refactoring."
        signals.filesModified = ["/a.swift"]

        XCTAssertTrue(strategy.shouldGenerateFirstTitle(for: signals))
    }

    func testGateFailsWithNoTurns() {
        var signals = SessionSignals(sessionID: "s1")
        signals.turnCount = 0

        XCTAssertFalse(strategy.shouldGenerateFirstTitle(for: signals))
    }

    func testGateFailsWithTurnsButNoProgress() {
        var signals = SessionSignals(sessionID: "s1")
        signals.turnCount = 2

        XCTAssertFalse(strategy.shouldGenerateFirstTitle(for: signals))
    }

    // MARK: - Title Dedup (tested via TitleStore)

    // MARK: - Normalization Unit Tests

    func testNormalizeRemovesXMLTags() {
        let result = RuleTitleStrategy.normalizeText("<local-command-stdout>some output</local-command-stdout> 帮我看看")
        XCTAssertFalse(result.contains("<local"))
        XCTAssertTrue(result.contains("帮我看看"))
    }

    func testNormalizeBareURLFiltered() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["https://example.com"]
        signals.firstUserIntent = "检查这个网站"

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.hasPrefix("https://"))
        XCTAssertTrue(result.text.contains("检查"))
    }

    func testURLWithIntentStripsURLKeepsIntent() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["https://github.com/foo/bar 帮我安装这个"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertTrue(result.text.contains("帮我安装"))
        XCTAssertFalse(result.text.contains("https://"))
    }

    func testURLDominatedTitleStripped() {
        var signals = SessionSignals(sessionID: "s1")
        signals.historyDisplayTexts = ["https://docs.openclaw.ai/ 安装一个最新的openclaw"]

        let result = strategy.generateTitle(from: signals)
        XCTAssertFalse(result.text.contains("https://"))
        XCTAssertTrue(result.text.contains("安装"))
    }

    // MARK: - Placeholder Title Tests

    func testPlaceholderForFailedResume() {
        var signals = SessionSignals(sessionID: "s1")
        signals.slashCommands = ["/resume"]
        signals.commandErrors = ["No conversations found to resume"]

        let result = strategy.generatePlaceholderTitle(from: signals)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.source, .placeholder)
        XCTAssertTrue(result!.text.contains("恢复会话失败"))
    }

    func testPlaceholderForInterruptedLogin() {
        var signals = SessionSignals(sessionID: "s1")
        signals.slashCommands = ["/login"]
        signals.commandErrors = ["Login interrupted"]

        let result = strategy.generatePlaceholderTitle(from: signals)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.source, .placeholder)
        XCTAssertTrue(result!.text.contains("登录中断"))
    }

    func testPlaceholderForClear() {
        var signals = SessionSignals(sessionID: "s1")
        signals.slashCommands = ["/clear"]

        let result = strategy.generatePlaceholderTitle(from: signals)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.text.contains("清屏"))
    }

    func testPlaceholderWithUserText() {
        var signals = SessionSignals(sessionID: "s1")
        signals.firstUserIntent = "conversation"

        let result = strategy.generatePlaceholderTitle(from: signals)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.text.contains("会话"))
    }

    func testPlaceholderNilForCompletelyEmpty() {
        let signals = SessionSignals(sessionID: "s1")
        let result = strategy.generatePlaceholderTitle(from: signals)
        XCTAssertNil(result)
    }

    func testPlaceholderSourceIsPlaceholderNotRule() {
        var signals = SessionSignals(sessionID: "s1")
        signals.slashCommands = ["/resume"]

        let result = strategy.generatePlaceholderTitle(from: signals)
        XCTAssertEqual(result?.source, .placeholder)
    }

    // MARK: - Placeholder → Real Title Upgrade (TitleStore level)

    func testPlaceholderDoesNotBlockRealTitle() {
        // Simulate: placeholder stored, then real title generated
        let dir = NSTemporaryDirectory() + "title-upgrade-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = TitleStore(directory: dir)
        let placeholder = GeneratedTitle(text: "恢复会话失败", source: .placeholder, generatedAt: Date())
        store.setTitle(for: "s1", title: placeholder)

        // Verify placeholder is current
        XCTAssertEqual(store.currentTitle(for: "s1")?.source, .placeholder)

        // Real title should be allowed to overwrite
        let real = GeneratedTitle(text: "重构 auth middleware", source: .rule, generatedAt: Date())
        store.setTitle(for: "s1", title: real)

        XCTAssertEqual(store.currentTitle(for: "s1")?.text, "重构 auth middleware")
        XCTAssertEqual(store.currentTitle(for: "s1")?.source, .rule)
        // History should have both entries
        XCTAssertEqual(store.titleHistory(for: "s1").count, 2)
    }
}
