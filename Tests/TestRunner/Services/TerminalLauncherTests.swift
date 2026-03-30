import Foundation
@testable import ClaudeSessionHubLib

enum TerminalLauncherTests {
    static func run() {
        print("── TerminalLauncherTests ──")
        testCopyCommandFormat()
        testCopyCommandWithoutCwd()
        testCopyCommandEscapesSpaces()
        testCopyCommandWithSpecialChars()
    }

    static func testCopyCommandFormat() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/Users/test/OACP",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        assertEqual(command, "cd /Users/test/OACP && claude -r abc-123")
    }

    static func testCopyCommandWithoutCwd() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: nil,
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        assertEqual(command, "claude -r abc-123")
    }

    static func testCopyCommandEscapesSpaces() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/Users/test/my project",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        check(command.contains("\"/Users/test/my project\"") || command.contains("my\\ project"),
              "spaces in cwd should be escaped/quoted, got: \(command)")
    }

    static func testCopyCommandWithSpecialChars() {
        // Chinese characters in path (real scenario on this machine)
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/Users/test/claude任务管理器",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        check(command.contains("claude任务管理器"), "Chinese path should be preserved, got: \(command)")
    }
}
