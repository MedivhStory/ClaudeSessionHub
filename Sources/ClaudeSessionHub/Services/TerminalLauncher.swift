import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum TerminalLauncher {
    public enum Terminal: String, CaseIterable, Sendable {
        case ghostty = "Ghostty"
        case terminalApp = "Terminal"
    }

    /// Tri-state for cwd availability — lets UI distinguish "never had cwd" from "cwd deleted"
    public enum CwdStatus: Sendable {
        case exists
        case missing
        case unknown
    }

    /// Check the cwd status for a ResumeTarget
    public static func cwdStatus(for target: ResumeTarget) -> CwdStatus {
        guard let cwd = target.workingDirectory else { return .unknown }
        return FileManager.default.fileExists(atPath: cwd) ? .exists : .missing
    }

    /// Build the shell command string for clipboard copy.
    /// Omits `cd` prefix if cwd is nil or doesn't exist on disk.
    public static func copyCommand(for target: ResumeTarget) -> String {
        if let cwd = target.workingDirectory,
           FileManager.default.fileExists(atPath: cwd) {
            let escaped = cwd.contains(" ") ? "\"\(cwd)\"" : cwd
            return "cd \(escaped) && \(target.displayCommand)"
        }
        return target.displayCommand
    }

    /// Copy string to system clipboard
    public static func copyToClipboard(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// Attempt to launch terminal with resume command.
    /// If the selected terminal is unavailable, falls back to the other.
    /// If both unavailable, falls back to clipboard copy + notification.
    public static func launch(target: ResumeTarget, in terminal: Terminal) {
        let shellCommand = copyCommand(for: target)

        if isTerminalAvailable(terminal) {
            do {
                try launchInTerminal(shellCommand: shellCommand, terminal: terminal)
                return
            } catch {}
        }

        let fallback: Terminal = (terminal == .ghostty) ? .terminalApp : .ghostty
        if isTerminalAvailable(fallback) {
            do {
                try launchInTerminal(shellCommand: shellCommand, terminal: fallback)
                return
            } catch {}
        }

        copyToClipboard(shellCommand)
        switch cwdStatus(for: target) {
        case .missing:
            sendNotification(message: "原目录不存在，已复制命令，请在终端粘贴执行")
        case .exists, .unknown:
            sendNotification(message: "已复制命令，请在终端粘贴执行")
        }
    }

    // MARK: - Preflight availability checks

    public static func isTerminalAvailable(_ terminal: Terminal) -> Bool {
        switch terminal {
        case .ghostty:
            if FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") { return true }
            return isCommandInPath("ghostty")
        case .terminalApp:
            return FileManager.default.fileExists(atPath: "/System/Applications/Utilities/Terminal.app")
                || FileManager.default.fileExists(atPath: "/Applications/Utilities/Terminal.app")
        }
    }

    private static func isCommandInPath(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Launch argument builders (pure, testable)

    /// Build the argv for Ghostty launch.
    /// Ghostty -e expects a program + args, NOT a shell expression.
    /// We wrap in /bin/zsh -lc "..." so shell syntax (cd && ...) works.
    public static func ghosttyLaunchArguments(for shellCommand: String) -> (executable: String, arguments: [String]) {
        if FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") {
            return (
                executable: "/usr/bin/open",
                arguments: ["-na", "Ghostty.app", "--args", "-e", "/bin/zsh", "-lc", shellCommand]
            )
        } else {
            return (
                executable: "/usr/bin/env",
                arguments: ["ghostty", "-e", "/bin/zsh", "-lc", shellCommand]
            )
        }
    }

    // MARK: - Launch helpers

    private static func launchInTerminal(shellCommand: String, terminal: Terminal) throws {
        switch terminal {
        case .ghostty:
            try launchGhostty(shellCommand: shellCommand)
        case .terminalApp:
            try launchTerminalApp(shellCommand: shellCommand)
        }
    }

    private static func launchGhostty(shellCommand: String) throws {
        let launch = ghosttyLaunchArguments(for: shellCommand)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        try process.run()
    }

    private static func launchTerminalApp(shellCommand: String) throws {
        let tmpFile = NSTemporaryDirectory() + "claude-hub-resume-\(UUID().uuidString).command"
        let script = "#!/bin/zsh -l\n\(shellCommand)\nrm -f \"\(tmpFile)\"\n"
        try script.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", tmpFile]
        try process.run()
    }

    private static func sendNotification(message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(message)\" with title \"Claude Session Hub\""]
        try? process.run()
    }
}
