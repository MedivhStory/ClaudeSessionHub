import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum TerminalLauncher {
    public enum Terminal: String, CaseIterable, Sendable {
        case ghostty = "Ghostty"
        case terminalApp = "Terminal"
    }

    /// Build the shell command string for clipboard copy
    public static func copyCommand(for target: ResumeTarget) -> String {
        if let cwd = target.workingDirectory {
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

    /// Attempt to launch terminal with resume command. Silent fallback to clipboard on failure.
    public static func launch(target: ResumeTarget, in terminal: Terminal) {
        let command = copyCommand(for: target)

        do {
            switch terminal {
            case .ghostty:
                try launchGhostty(command: command)
            case .terminalApp:
                try launchTerminalApp(command: command)
            }
        } catch {
            // Silent fallback: copy to clipboard + notification
            copyToClipboard(command)
            sendNotification(message: "已复制命令，请在终端粘贴执行")
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
