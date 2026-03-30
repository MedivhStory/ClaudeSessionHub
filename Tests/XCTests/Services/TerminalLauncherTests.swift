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

    func testCwdExistsCheck() {
        let existing = ResumeTarget(executable: "claude", arguments: [],
                                    workingDirectory: "/tmp", displayCommand: "claude")
        XCTAssertTrue(TerminalLauncher.cwdExists(for: existing))

        let missing = ResumeTarget(executable: "claude", arguments: [],
                                   workingDirectory: "/nonexistent", displayCommand: "claude")
        XCTAssertFalse(TerminalLauncher.cwdExists(for: missing))

        let noCwd = ResumeTarget(executable: "claude", arguments: [],
                                 workingDirectory: nil, displayCommand: "claude")
        XCTAssertFalse(TerminalLauncher.cwdExists(for: noCwd))
    }
}
