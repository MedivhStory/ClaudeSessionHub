import Foundation

/// Protocol for title generation — v0.2.5+ LLM slot.
/// v0.2.0 ships only `RuleTitleStrategy`.
public protocol SessionTitleStrategy: Sendable {
    func generateTitle(from signals: SessionSignals) -> GeneratedTitle
    func generatePlaceholderTitle(from signals: SessionSignals) -> GeneratedTitle?
    func extractLastProgress(from signals: SessionSignals) -> String?
    func shouldGenerateFirstTitle(for signals: SessionSignals) -> Bool
}

/// Rule-based title generation. Fully offline, no API dependencies.
public struct RuleTitleStrategy: SessionTitleStrategy, Sendable {

    private let maxTitleLength = 50
    private let maxProgressLength = 120

    public init() {}

    // MARK: - Title Generation

    public func generateTitle(from signals: SessionSignals) -> GeneratedTitle {
        let text = bestTitleCandidate(from: signals)
        return GeneratedTitle(text: text, source: .rule, generatedAt: Date())
    }

    private func bestTitleCandidate(from signals: SessionSignals) -> String {
        // Priority 1: history.jsonl display text (user's actual typed command)
        if let historyTitle = bestHistoryDisplay(signals.historyDisplayTexts) {
            return truncate(historyTitle, to: maxTitleLength)
        }

        // Priority 2: tasks/ subject (structured goal)
        if let subject = signals.taskSubject, !subject.isEmpty {
            return truncate(subject, to: maxTitleLength)
        }

        // Priority 3: First user intent from JSONL (also normalized)
        if let intent = signals.firstUserIntent {
            let cleaned = normalizeText(intent)
            if isMeaningfulTitle(cleaned) {
                return truncate(cleaned, to: maxTitleLength)
            }
        }

        // Priority 4: slug (if not random pattern)
        if let slug = signals.slug, !slug.isEmpty, !isRandomSlug(slug) {
            return truncate(slug, to: maxTitleLength)
        }

        // Priority 5: sessionID prefix
        return String(signals.sessionID.prefix(8))
    }

    // MARK: - History Display Cleaning

    /// Select the best history display text, applying full normalization pipeline.
    private func bestHistoryDisplay(_ texts: [String]) -> String? {
        for text in texts {
            let cleaned = normalizeText(text)
            guard isMeaningfulTitle(cleaned) else { continue }

            // If it's a shell command with trailing intent, extract the intent
            if let intent = extractIntentFromCommand(cleaned) {
                return intent
            }

            // If it's purely a shell command, skip — try next entry
            if isShellCommandLike(cleaned) { continue }

            return cleaned
        }
        return nil
    }

    /// Full normalization pipeline for raw history/intent text.
    static func normalizeText(_ text: String) -> String {
        var t = text

        // 1. Collapse to single line (replace newlines with spaces)
        t = t.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 2. Remove [Pasted text #N +M lines] anywhere
        if let regex = try? NSRegularExpression(pattern: "\\[Pasted text.*?\\]", options: .caseInsensitive) {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }

        // 3. Remove XML/internal tags like <local-command-stdout>, <system-reminder>, etc.
        if let regex = try? NSRegularExpression(pattern: "<[a-zA-Z-]+>.*?</[a-zA-Z-]+>", options: .dotMatchesLineSeparators) {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        // Also self-closing or unclosed tags
        if let regex = try? NSRegularExpression(pattern: "</?[a-zA-Z-]+/?>") {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }

        // 4. Strip URLs — keep surrounding natural language
        if let regex = try? NSRegularExpression(pattern: "https?://\\S+") {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }

        // 5. Strip shell-escaped spaces (e.g. "OACP\ ai\ team" → "OACP ai team")
        t = t.replacingOccurrences(of: "\\ ", with: " ")

        // 6. Strip file references: absolute paths and filename.ext patterns
        // Strategy: find segments that look like file paths and remove them.
        // This handles /Users/.../file.ext, ~/path, and escaped paths after step 5.
        t = Self.stripFileReferences(t)

        // 7. Strip terminal prompt/dialog chars
        let promptChars = CharacterSet(charactersIn: "▎▏▐▕│┃►▶❯❱›»$#%>")
        t = String(t.unicodeScalars.filter { !promptChars.contains($0) })

        // 8. Compress whitespace
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        return t
    }

    /// Remove file path references from text.
    /// Strategy: find text starting with / or ~/ up through a file extension (.ext),
    /// which handles both simple paths and shell-escaped paths (after unescape).
    private static func stripFileReferences(_ text: String) -> String {
        var result = text

        // Pattern 1: Path ending with .extension (handles spaces in path after unescape)
        // Matches: /anything.ext or ~/anything.ext — greedy up to the last .ext
        if let regex = try? NSRegularExpression(pattern: "~?/[^\\n]*?\\.\\w{1,10}(?=\\s|$)") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Pattern 2: Deep paths without extension (3+ segments, no spaces — simple paths only)
        if let regex = try? NSRegularExpression(pattern: "~?/(?:[^/\\s]+/){2,}[^/\\s]+") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        return result
    }

    // Keep non-static version for internal use
    private func normalizeText(_ text: String) -> String {
        Self.normalizeText(text)
    }

    /// Check if cleaned text is worth using as a title.
    private func isMeaningfulTitle(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Too short
        if t.count < 4 { return false }
        // Slash commands
        if t.hasPrefix("/") { return false }
        // Bare URL with no other content
        if (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(" ") { return false }
        return true
    }

    // MARK: - Shell Command Detection

    private static let shellCommands: Set<String> = [
        "npx", "npm", "pnpm", "yarn", "bun",
        "git", "gh",
        "python", "python3", "pip", "pip3", "uv",
        "bash", "sh", "zsh",
        "curl", "wget",
        "swift", "xcodebuild", "swiftc",
        "claude", "codex",
        "cd", "ls", "rm", "cp", "mv", "mkdir", "cat", "grep", "find",
        "brew", "apt", "dnf",
        "docker", "kubectl",
        "node", "deno", "tsx",
        "make", "cmake",
        "cargo", "go", "rustc",
        "ssh", "scp", "rsync",
        "sudo", "env",
    ]

    /// Returns true if the text looks primarily like a shell command invocation.
    private func isShellCommandLike(_ text: String) -> Bool {
        let firstToken = text.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
        return Self.shellCommands.contains(firstToken)
    }

    /// If text is "command args ... natural language intent", try to extract the intent.
    /// Returns nil if no clear intent portion found.
    private func extractIntentFromCommand(_ text: String) -> String? {
        let firstToken = text.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
        guard Self.shellCommands.contains(firstToken) else { return nil }

        // Look for Chinese text after the command — that's likely the intent
        let chinesePattern = "[\\u4e00-\\u9fff]"
        guard let regex = try? NSRegularExpression(pattern: chinesePattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }

        // Extract from first Chinese char to end
        let intent = String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return intent.count >= 4 ? intent : nil
    }

    private func isRandomSlug(_ slug: String) -> Bool {
        let pattern = "^[a-z]{4,}-[a-z]{4,}-[a-z]{4,}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: slug, range: NSRange(slug.startIndex..., in: slug)) != nil
    }

    // MARK: - Placeholder Title (for gate-failed sessions)

    /// Generate a descriptive placeholder for sessions that don't pass the generation gate.
    /// Returns nil only if no recognizable pattern is found (ultimate fallback to sessionID).
    public func generatePlaceholderTitle(from signals: SessionSignals) -> GeneratedTitle? {
        let text = placeholderText(from: signals)
        guard let text else { return nil }
        return GeneratedTitle(text: text, source: .placeholder, generatedAt: Date())
    }

    private func placeholderText(from signals: SessionSignals) -> String? {
        let cmds = signals.slashCommands
        let errors = signals.commandErrors

        // Pattern: failed /resume
        if cmds.contains(where: { $0.contains("resume") }) {
            if errors.contains(where: { $0.lowercased().contains("not found") || $0.lowercased().contains("no conversation") }) {
                return "恢复会话失败：未找到可恢复会话"
            }
            return "恢复会话（无后续操作）"
        }

        // Pattern: /login attempts
        if cmds.contains(where: { $0.contains("login") }) {
            if errors.contains(where: { $0.lowercased().contains("interrupt") }) {
                return "登录中断"
            }
            return "登录会话"
        }

        // Pattern: /clear only
        if cmds.contains(where: { $0.contains("clear") }) {
            return "清屏操作"
        }

        // Pattern: has some user text but no real task progress
        if let intent = signals.firstUserIntent, !intent.isEmpty {
            let cleaned = Self.normalizeText(intent)
            if !cleaned.isEmpty && cleaned.count >= 2 {
                return truncate("会话: \(cleaned)", to: maxTitleLength)
            }
        }

        // Pattern: has slash commands but unrecognized
        if !cmds.isEmpty {
            let cmdList = cmds.joined(separator: ", ")
            return truncate("命令会话: \(cmdList)", to: maxTitleLength)
        }

        // Pattern: has assistant reply but gate still failed (edge case)
        if signals.hasAssistantReply && signals.turnCount > 0 {
            return "会话进行中（尚无明确进展）"
        }

        return nil
    }

    // MARK: - Last Progress Extraction

    public func extractLastProgress(from signals: SessionSignals) -> String? {
        // Priority 1: Assistant's completion statement
        if let progress = signals.lastAssistantProgress, !progress.isEmpty {
            return truncate(progress, to: maxProgressLength)
        }

        // Priority 2: Task with completed/in_progress status
        if let subject = signals.taskSubject, let status = signals.taskStatus {
            let statusLabel: String
            switch status {
            case "completed": statusLabel = "✓ 完成"
            case "in_progress": statusLabel = "进行中"
            case "blocked": statusLabel = "⚠ 阻塞"
            default: statusLabel = status
            }
            return truncate("\(statusLabel): \(subject)", to: maxProgressLength)
        }

        // No fallback to user intent — "最后进展" answers "最近完成了什么",
        // not "用户最后说了什么". Return nil if no completion signal found.
        return nil
    }

    // MARK: - First Generation Gate

    public func shouldGenerateFirstTitle(for signals: SessionSignals) -> Bool {
        // Gate 1: At least one complete user → assistant round-trip.
        guard signals.turnCount >= 1 else { return false }
        let hasAssistantResponse = signals.lastAssistantProgress != nil || !signals.toolsUsed.isEmpty

        // Gate 2: At least one meaningful progress signal
        let hasFileModification = !signals.filesModified.isEmpty
        let hasTaskProgress = signals.taskStatus != nil
        let hasAssistantProgress = signals.lastAssistantProgress != nil && !signals.lastAssistantProgress!.isEmpty
        let hasToolUsage = !signals.toolsUsed.isEmpty

        return hasAssistantResponse && (hasFileModification || hasTaskProgress || hasAssistantProgress || hasToolUsage)
    }

    // MARK: - Helpers

    private func truncate(_ s: String, to maxLen: Int) -> String {
        if s.count <= maxLen { return s }
        return String(s.prefix(maxLen - 1)) + "…"
    }
}
