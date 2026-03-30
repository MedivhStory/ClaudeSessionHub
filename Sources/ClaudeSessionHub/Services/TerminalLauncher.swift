import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum TerminalLauncher {
    public enum Terminal: String, CaseIterable, Sendable {
        case ghostty = "Ghostty"
        case terminalApp = "Terminal"
    }

    /// Build the shell command string for clipboard copy.
    /// Checks if cwd exists — if not, omits the `cd` prefix (spec: "原目录不存在").
    public static func copyCommand(for target: ResumeTarget) -> String {
        if let cwd = target.workingDirectory,
           FileManager.default.fileExists(atPath: cwd) {
            let escaped = cwd.contains(" ") ? "\"\(cwd)\"" : cwd
            return "cd \(escaped) && \(target.displayCommand)"
        }
        return target.displayCommand
    }

    /// Whether the cwd in a ResumeTarget still exists on disk.
    public static func cwdExists(for target: ResumeTarget) -> Bool {
        guard let cwd = target.workingDirectory else { return false }
        return FileManager.default.fileExists(atPath: cwd)
    }

    /// Copy string to system clipboard
    public static func copyToClipboard(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// Attempt to launch terminal with resume command.
    /// If the selected terminal fails, falls back to the other terminal.
    /// If both fail, falls back to clipboard copy + notification.
    public static func launch(target: ResumeTarget, in terminal: Terminal) {
        let command = copyCommand(for: target)

        // Try the selected terminal first
        if tryLaunch(command: command, terminal: terminal) { return }

        // Fallback to the other supported terminal (spec: "Ghostty not installed → Fall back to Terminal.app")
        let fallbackTerminal: Terminal = (terminal == .ghostty) ? .terminalApp : .ghostty
        if tryLaunch(command: command, terminal: fallbackTerminal) { return }

        // Both failed — silent clipboard fallback
        copyToClipboard(command)
        if target.workingDirectory != nil && !cwdExists(for: target) {
            sendNotification(message: "原目录不存在，已复制命令，请在终端粘贴执行")
        } else {
            sendNotification(message: "已复制命令，请在终端粘贴执行")
        }
    }

    /// Returns true if launch succeeded
    private static func tryLaunch(command: String, terminal: Terminal) -> Bool {
        do {
            switch terminal {
            case .ghostty:
                try launchGhostty(command: command)
            case .terminalApp:
                try launchTerminalApp(command: command)
            }
            return true
        } catch {
            return false
        }
    }

    private static func launchGhostty(command: String) throws {
        let ghosttyPath = "/Applications/Ghostty.app"
        if FileManager.default.fileExists(atPath: ghosttyPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-na", "Ghostty.app", "--args", "-e", command]
            try process.run()
        } else {
            // Try CLI in PATH
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["ghostty", "-e", command]
            try process.run()
        }
    }

    private static func launchTerminalApp(command: String) throws {
        let tmpFile = NSTemporaryDirectory() + "claude-hub-resume-\(UUID().uuidString).command"
        let script = "#!/bin/bash\n\(command)\nrm -f \"\(tmpFile)\"\n"
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
