import XCTest
@testable import ClaudeSessionHubLib

final class TerminalLauncherXCTests: XCTestCase {

    func testCopyCommandFormat() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/Users/test/OACP",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertEqual(command, "cd /Users/test/OACP && claude -r abc-123")
    }

    func testCopyCommandWithoutCwd() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: nil,
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertEqual(command, "claude -r abc-123")
    }

    func testCopyCommandEscapesSpaces() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/Users/test/my project",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertTrue(command.contains("\"/Users/test/my project\"") || command.contains("my\\ project"),
                      "spaces in cwd should be escaped/quoted, got: \(command)")
    }

    func testCopyCommandWithSpecialChars() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/Users/test/claude任务管理器",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertTrue(command.contains("claude任务管理器"),
                      "Chinese path should be preserved, got: \(command)")
    }
}
