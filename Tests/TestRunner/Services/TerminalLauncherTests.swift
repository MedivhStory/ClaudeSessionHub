import Foundation
@testable import ClaudeSessionHubLib

enum TerminalLauncherTests {
    static func run() {
        print("── TerminalLauncherTests ──")
        testCopyCommandWithExistingCwd()
        testCopyCommandWithoutCwd()
        testCopyCommandWithMissingCwdOmitsCd()
        testCopyCommandEscapesSpaces()
        testCwdStatusTriState()
        testTerminalAvailability()
        testGhosttyLaunchUsesShellWrapper()
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

    static func testCwdStatusTriState() {
        let existing = ResumeTarget(executable: "claude", arguments: [],
                                    workingDirectory: "/tmp", displayCommand: "claude")
        if case .exists = TerminalLauncher.cwdStatus(for: existing) {} else {
            check(false, "/tmp should be .exists")
        }

        let missing = ResumeTarget(executable: "claude", arguments: [],
                                   workingDirectory: "/nonexistent/deleted/project", displayCommand: "claude")
        if case .missing = TerminalLauncher.cwdStatus(for: missing) {} else {
            check(false, "deleted path should be .missing")
        }

        let noCwd = ResumeTarget(executable: "claude", arguments: [],
                                 workingDirectory: nil, displayCommand: "claude")
        if case .unknown = TerminalLauncher.cwdStatus(for: noCwd) {} else {
            check(false, "nil cwd should be .unknown")
        }
    }

    static func testTerminalAvailability() {
        check(TerminalLauncher.isTerminalAvailable(.terminalApp), "Terminal.app should be available on macOS")
    }

    static func testGhosttyLaunchUsesShellWrapper() {
        // Ghostty -e expects argv, not shell expressions.
        // We must wrap in /bin/zsh -lc so "cd ... && claude -r ..." works.
        let command = "cd /tmp && claude -r abc-123"
        let launch = TerminalLauncher.ghosttyLaunchArguments(for: command)

        // Must contain /bin/zsh and -lc to interpret shell syntax
        check(launch.arguments.contains("/bin/zsh"),
              "Ghostty args must include /bin/zsh, got: \(launch.arguments)")
        check(launch.arguments.contains("-lc"),
              "Ghostty args must include -lc for shell interpretation, got: \(launch.arguments)")
        check(launch.arguments.contains(command),
              "Ghostty args must include the shell command, got: \(launch.arguments)")

        // Must NOT pass the raw shell command directly to -e without shell wrapper
        // (this was the bug: -e "cd /path && claude -r id" fails because Ghostty
        // treats it as a program name, not a shell expression)
        if let eIndex = launch.arguments.firstIndex(of: "-e") {
            let afterE = launch.arguments[eIndex + 1]
            check(afterE == "/bin/zsh",
                  "After -e must be /bin/zsh, not the raw command. Got: \(afterE)")
        }
    }
}
