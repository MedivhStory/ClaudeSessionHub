import Foundation
@testable import ClaudeSessionHubLib

enum TerminalLauncherTests {
    static func run() {
        print("── TerminalLauncherTests ──")
        testCopyCommandWithExistingCwd()
        testCopyCommandWithoutCwd()
        testCopyCommandWithMissingCwdOmitsCd()
        testCopyCommandEscapesSpaces()
        testCwdExistsCheck()
    }

    static func testCopyCommandWithExistingCwd() {
        // Use /tmp which always exists
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/tmp",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        assertEqual(command, "cd /tmp && claude -r abc-123")
    }

    static func testCopyCommandWithoutCwd() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: nil,
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        assertEqual(command, "claude -r abc-123")
    }

    static func testCopyCommandWithMissingCwdOmitsCd() {
        // Spec: cwd missing → execute without cd, show notice "原目录不存在"
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/nonexistent/path/that/does/not/exist",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        // Should NOT have "cd" prefix since the directory doesn't exist
        assertEqual(command, "claude -r abc-123", "missing cwd should omit cd prefix")
    }

    static func testCopyCommandEscapesSpaces() {
        // Create a temp dir with spaces to test quoting
        let spacedDir = NSTemporaryDirectory() + "my project \(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: spacedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: spacedDir) }

        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: spacedDir,
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        check(command.hasPrefix("cd \""), "spaces in cwd should be quoted, got: \(command)")
        check(command.contains("my project"), "path with spaces should be preserved")
    }

    static func testCwdExistsCheck() {
        let existing = ResumeTarget(executable: "claude", arguments: [],
                                    workingDirectory: "/tmp", displayCommand: "claude")
        check(TerminalLauncher.cwdExists(for: existing), "/tmp should exist")

        let missing = ResumeTarget(executable: "claude", arguments: [],
                                   workingDirectory: "/nonexistent", displayCommand: "claude")
        check(!TerminalLauncher.cwdExists(for: missing), "/nonexistent should not exist")

        let noCwd = ResumeTarget(executable: "claude", arguments: [],
                                 workingDirectory: nil, displayCommand: "claude")
        check(!TerminalLauncher.cwdExists(for: noCwd), "nil cwd should return false")
    }
}
