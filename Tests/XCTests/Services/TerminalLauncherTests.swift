import XCTest
@testable import ClaudeSessionHubLib

final class TerminalLauncherXCTests: XCTestCase {

    func testCopyCommandWithExistingCwd() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/tmp",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertEqual(command, "cd /tmp && claude -r abc-123")
    }

    func testCopyCommandWithoutCwd() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: nil,
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertEqual(command, "claude -r abc-123")
    }

    func testCopyCommandWithMissingCwdOmitsCd() {
        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: "/nonexistent/path/that/does/not/exist",
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertEqual(command, "claude -r abc-123", "missing cwd should omit cd prefix")
    }

    func testCopyCommandEscapesSpaces() throws {
        let spacedDir = NSTemporaryDirectory() + "my project \(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: spacedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: spacedDir) }

        let target = ResumeTarget(executable: "claude", arguments: ["-r", "abc-123"],
                                  workingDirectory: spacedDir,
                                  displayCommand: "claude -r abc-123")
        let command = TerminalLauncher.copyCommand(for: target)
        XCTAssertTrue(command.hasPrefix("cd \""), "spaces in cwd should be quoted, got: \(command)")
    }

    func testCwdStatusTriState() {
        let existing = ResumeTarget(executable: "claude", arguments: [],
                                    workingDirectory: "/tmp", displayCommand: "claude")
        if case .exists = TerminalLauncher.cwdStatus(for: existing) {} else {
            XCTFail("/tmp should be .exists")
        }

        let missing = ResumeTarget(executable: "claude", arguments: [],
                                   workingDirectory: "/nonexistent/deleted", displayCommand: "claude")
        if case .missing = TerminalLauncher.cwdStatus(for: missing) {} else {
            XCTFail("deleted path should be .missing")
        }

        let noCwd = ResumeTarget(executable: "claude", arguments: [],
                                 workingDirectory: nil, displayCommand: "claude")
        if case .unknown = TerminalLauncher.cwdStatus(for: noCwd) {} else {
            XCTFail("nil cwd should be .unknown")
        }
    }

    func testTerminalAvailability() {
        XCTAssertTrue(TerminalLauncher.isTerminalAvailable(.terminalApp), "Terminal.app should be available")
    }

    func testGhosttyLaunchUsesShellWrapper() {
        let command = "cd /tmp && claude -r abc-123"
        let launch = TerminalLauncher.ghosttyLaunchArguments(for: command)

        XCTAssertTrue(launch.arguments.contains("/bin/zsh"), "Must use /bin/zsh")
        XCTAssertTrue(launch.arguments.contains("-lc"), "Must use -lc for shell")
        XCTAssertTrue(launch.arguments.contains(command), "Must include shell command")

        if let eIndex = launch.arguments.firstIndex(of: "-e") {
            XCTAssertEqual(launch.arguments[eIndex + 1], "/bin/zsh",
                          "After -e must be /bin/zsh, not raw shell command")
        }
    }
}
