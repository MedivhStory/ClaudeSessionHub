import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// @unchecked Sendable safety: ClaudeProvider has no mutable instance state.
/// All state in discoverSessions/buildSummary is local.
/// baseDirectoryProvider is a closure that returns the current path (supports hot-switch).
public final class ClaudeProvider: AgentProvider, @unchecked Sendable {
    public let id: ProviderID = "claude"
    public let displayName = "Claude Code"
    public let capabilities: ProviderCapabilities = [.resume, .contextUsage, .errorTracking, .branchInfo]

    private let baseDirectoryProvider: @Sendable () -> String

    /// Read-only accessor for the current base directory (evaluated each call).
    private var baseDirectory: String { baseDirectoryProvider() }

    public init(baseDirectory: String? = nil) {
        let dir = baseDirectory ?? (NSHomeDirectory() + "/.claude")
        self.baseDirectoryProvider = { dir }
    }

    /// Initialize with a dynamic directory provider (for hot-switch support).
    public init(baseDirectoryProvider: @escaping @Sendable () -> String) {
        self.baseDirectoryProvider = baseDirectoryProvider
    }

    // MARK: - discoverSessions

    public func discoverSessions() async throws -> [SessionSummary] {
        // All mutable state is local — no shared instance vars to race on.
        let metadata = loadSessionMetadata()
        let fm = FileManager.default
        let projectsDir = baseDirectory + "/projects"

        guard fm.fileExists(atPath: projectsDir) else { return [] }

        var jsonlFiles: [String] = []
        // Scan projects/*/  for *.jsonl files (top-level only, no recursion into subdirectories)
        if let topLevelContents = try? fm.contentsOfDirectory(atPath: projectsDir) {
            for projectDir in topLevelContents {
                let projectPath = projectsDir + "/" + projectDir
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }
                // Skip memory dirs
                if projectDir == "memory" { continue }
                // Skip subagents
                if projectPath.contains("/subagents/") { continue }

                if let files = try? fm.contentsOfDirectory(atPath: projectPath) {
                    for file in files {
                        guard file.hasSuffix(".jsonl") else { continue }
                        let fullPath = projectPath + "/" + file
                        // Skip paths containing subagents
                        if fullPath.contains("/subagents/") { continue }
                        jsonlFiles.append(fullPath)
                    }
                }
            }
        }

        var summaries: [SessionSummary] = []
        for path in jsonlFiles {
            if let summary = try? buildSummary(from: path, metadata: metadata) {
                // Skip empty sessions — files with only snapshots/system entries
                // and zero user turns are not real conversations
                if summary.turnCount == 0 && summary.currentTaskSummary == nil {
                    continue
                }
                summaries.append(summary)
            }
        }
        return summaries
    }

    // MARK: - Build Summary

    /// All state is passed in or local — no shared mutable instance vars.
    private func buildSummary(from path: String, metadata: [String: (pid: Int32, startedAt: Date?)]) throws -> SessionSummary {
        let firstEntries = try JSONLParser.readFirstEntries(at: path, count: 10)
        // Read more tail entries (50) so recentErrorCount has enough turns to sample from.
        // 20 user turns can easily span 40-60 entries (interleaved assistant/system/progress).
        let lastEntries = try JSONLParser.readLastEntries(at: path, count: 50)
        let allEntries = mergeEntries(first: firstEntries, last: lastEntries)

        // Session ID from filename
        let filename = (path as NSString).lastPathComponent
        let sessionID = String(filename.dropLast(6)) // remove .jsonl

        let ref = SessionRef(providerID: id, sessionID: sessionID)

        // Extract cwd from entries
        let cwd = extractCwd(from: allEntries)

        // Extract branch
        let branch = extractBranch(from: allEntries)

        // Title extraction
        let title = extractTitle(from: allEntries, sessionID: sessionID)

        // currentTaskSummary
        let taskSummary = extractCurrentTaskSummary(from: allEntries)

        // contextUsage
        let contextUsage = extractContextUsage(from: allEntries)

        // filesTouched
        let filesTouched = extractFilesTouched(from: allEntries)

        // recentErrorCount — from lastEntries only (tail of session), not merged
        let recentErrorCount = extractRecentErrorCount(from: lastEntries)

        // taskPhase
        let taskPhase = extractTaskPhase(from: allEntries)

        // turnCount
        let turnCount = countUserTurns(from: allEntries)

        // timestamps — prefer metadata startedAt for createdAt (spec: startedAt > JSONL first > birthtime)
        let createdAt = metadata[sessionID]?.startedAt
            ?? extractTimestamp(from: firstEntries.first)
            ?? Date()
        // Find last entry with a valid timestamp (some entries like last-prompt have no timestamp)
        let lastActiveAt = lastEntries.reversed().compactMap({ extractTimestamp(from: $0) }).first
            ?? extractTimestamp(from: firstEntries.last)
            ?? Date()

        // entrypoint
        let entrypoint = extractEntrypoint(from: allEntries)

        return SessionSummary(
            ref: ref,
            title: title,
            currentTaskSummary: taskSummary,
            runtimeState: .stopped,
            taskPhase: taskPhase,
            cwd: cwd,
            branch: branch,
            turnCount: turnCount,
            filesTouched: filesTouched,
            recentErrorCount: recentErrorCount,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt,
            contextUsage: contextUsage,
            entrypoint: entrypoint
        )
    }

    // MARK: - Entry Merging (dedup)

    private func mergeEntries(first: [[String: Any]], last: [[String: Any]]) -> [[String: Any]] {
        // Simple merge: first + last, dedup by checking if last entries overlap with first
        // Use timestamp + type as rough dedup key
        var result = first
        let firstTimestamps = Set(first.compactMap { entryKey($0) })
        for entry in last {
            if let key = entryKey(entry), !firstTimestamps.contains(key) {
                result.append(entry)
            }
        }
        return result
    }

    private func entryKey(_ entry: [String: Any]) -> String? {
        let ts = entry["timestamp"] as? String ?? String(describing: entry["timestamp"])
        let type = entry["type"] as? String ?? ""
        let uuid = entry["uuid"] as? String ?? ""
        if !uuid.isEmpty { return uuid }
        return "\(ts)_\(type)"
    }

    // MARK: - Title Extraction

    private func extractTitle(from entries: [[String: Any]], sessionID: String) -> String {
        let chinesePattern = "帮我|修复|重构|设计|实现|添加|创建|优化|调试|分析|配置|部署"
        let englishPattern = "^(fix|add|create|build|implement|refactor|debug|update|remove|setup|configure|write|test|review|check|run|generate|verify|read|use|proceed|stop|invoke|deploy|migrate|install|delete|move|rename|merge|push|pull|fetch|search|find|list|show|explain|analyze|clean|upgrade|downgrade|convert|parse|validate|publish|release|start|init|set|get|make|do|help|try|send|open|close|enable|disable|connect|disconnect)\\b"

        let nonMetaUserMessages = entries.filter { entry in
            guard entry["type"] as? String == "user" else { return false }
            guard entry["isMeta"] as? Bool != true else { return false }
            return true
        }

        // Check first 5 non-meta user messages for verb patterns
        let toCheck = Array(nonMetaUserMessages.prefix(5))
        for entry in toCheck {
            guard let content = extractStringContent(from: entry) else { continue }
            if matchesChineseVerb(content, pattern: chinesePattern) || matchesEnglishImperative(content, pattern: englishPattern) {
                return truncate(content, to: 40)
            }
        }

        // No verb match: use first non-meta message
        if let first = nonMetaUserMessages.first, let content = extractStringContent(from: first) {
            let candidate = truncate(content, to: 40)
            if !candidate.isEmpty {
                return candidate
            }
        }

        // Check slug field
        for entry in entries {
            if let slug = entry["slug"] as? String, !slug.isEmpty {
                let randomPattern = "^[a-z]+-[a-z]+-[a-z]+$"
                if let regex = try? NSRegularExpression(pattern: randomPattern),
                   regex.firstMatch(in: slug, range: NSRange(slug.startIndex..., in: slug)) == nil {
                    return truncate(slug, to: 40)
                }
            }
        }

        // Final fallback: first 8 chars of sessionID
        return String(sessionID.prefix(8))
    }

    private func extractStringContent(from entry: [String: Any]) -> String? {
        guard let message = entry["message"] as? [String: Any] else { return nil }
        // Claude Code JSONL user content can be:
        //   • a plain String (legacy shape for slash-command wrappers)
        //   • an array of content blocks; blocks can be:
        //       - `{ "type": "text", "text": "..." }`  → real user text
        //       - `{ "type": "tool_result", ... }`     → tool call return, NOT user intent
        //   We return the joined text of all text blocks (if any). Arrays
        //   containing only tool_result blocks return nil (treated as noise).
        if let content = message["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let blocks = message["content"] as? [[String: Any]] {
            var texts: [String] = []
            for block in blocks {
                guard block["type"] as? String == "text",
                      let text = block["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts.append(trimmed) }
            }
            if texts.isEmpty { return nil }
            return texts.joined(separator: " ")
        }
        return nil
    }

    private func matchesChineseVerb(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func matchesEnglishImperative(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - currentTaskSummary

    private func extractCurrentTaskSummary(from entries: [[String: Any]]) -> String? {
        // Reverse scan for last user entry that is:
        // - not isMeta
        // - has real text content (String or array-of-text-blocks; tool_result
        //   arrays are rejected by extractStringContent)
        // - not an internal command or system noise
        for entry in entries.reversed() {
            guard entry["type"] as? String == "user" else { continue }
            guard entry["isMeta"] as? Bool != true else { continue }
            guard let trimmed = extractStringContent(from: entry) else { continue }
            if trimmed.isEmpty { continue }
            if isInternalCommandNoise(trimmed) { continue }
            return truncate(trimmed, to: 80)
        }
        return nil
    }

    /// Returns true if the content is internal Claude Code command noise, not human intent
    private func isInternalCommandNoise(_ content: String) -> Bool {
        // XML-wrapped internal messages
        if content.hasPrefix("<local-command-stdout>") { return true }
        if content.hasPrefix("<local-command-caveat>") { return true }
        if content.hasPrefix("<command-name>") { return true }
        if content.hasPrefix("<task-notification>") { return true }
        if content.hasPrefix("<system-reminder>") { return true }
        // Slash commands
        if content.hasPrefix("/resume") { return true }
        if content.hasPrefix("/login") { return true }
        if content.hasPrefix("/logout") { return true }
        if content.hasPrefix("/clear") { return true }
        return false
    }

    // MARK: - contextUsage

    private func extractContextUsage(from entries: [[String: Any]]) -> ContextUsage? {
        // Find last real assistant entry with message.usage.
        // Skip <synthetic> sentinel entries that Claude Code appends with all-zero tokens.
        for entry in entries.reversed() {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            if message["model"] as? String == "<synthetic>" { continue }
            guard let usage = message["usage"] as? [String: Any] else { continue }

            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

            let modelName = message["model"] as? String ?? entry["model"] as? String
            let modelInfo = ModelInfo.resolve(modelName: modelName)

            return ContextUsage(
                inputTokens: inputTokens,
                cacheCreationTokens: cacheCreation,
                cacheReadTokens: cacheRead,
                limit: modelInfo.contextLimit
            )
        }
        return nil
    }

    // MARK: - filesTouched

    private func extractFilesTouched(from entries: [[String: Any]]) -> Int {
        var files = Set<String>()
        let toolNames: Set<String> = ["Edit", "Write", "MultiEdit"]

        for entry in entries {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            guard let contentArray = message["content"] as? [[String: Any]] else { continue }
            for item in contentArray {
                guard item["type"] as? String == "tool_use" else { continue }
                guard let name = item["name"] as? String, toolNames.contains(name) else { continue }
                if let input = item["input"] as? [String: Any],
                   let filePath = input["file_path"] as? String {
                    files.insert(filePath)
                }
            }
        }
        return files.count
    }

    // MARK: - recentErrorCount

    /// Count errors from tool_result.is_error in the last 20 user turns only.
    /// This ensures old errors from early debugging don't permanently flag a session.
    private func extractRecentErrorCount(from entries: [[String: Any]]) -> Int {
        // Collect the last 20 non-meta user turns, then count errors within them
        let recentUserEntries = entries.reversed()
            .filter { $0["type"] as? String == "user" && $0["isMeta"] as? Bool != true }
            .prefix(20)

        var count = 0
        for entry in recentUserEntries {
            guard let message = entry["message"] as? [String: Any] else { continue }
            guard let contentArray = message["content"] as? [[String: Any]] else { continue }
            for item in contentArray {
                guard item["type"] as? String == "tool_result" else { continue }
                if item["is_error"] as? Bool == true {
                    count += 1
                }
            }
        }
        return count
    }

    // MARK: - taskPhase

    private func extractTaskPhase(from entries: [[String: Any]]) -> TaskPhase {
        // Check last user message
        let donePattern = "已完成|done|merged|完成了"
        let blockedPattern = "等待|blocked|after merge|待确认"

        // Find last non-meta user message with string content
        for entry in entries.reversed() {
            guard entry["type"] as? String == "user" else { continue }
            guard entry["isMeta"] as? Bool != true else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            if let content = message["content"] as? String {
                if matchesPattern(content, pattern: donePattern) { return .done }
                if matchesPattern(content, pattern: blockedPattern) { return .blocked }
            }
            break // only check last one
        }

        // Check if last entries have tool_use -> inProgress
        for entry in entries.suffix(3).reversed() {
            if entry["type"] as? String == "assistant" {
                if let message = entry["message"] as? [String: Any],
                   let contentArray = message["content"] as? [[String: Any]] {
                    for item in contentArray {
                        if item["type"] as? String == "tool_use" {
                            return .inProgress
                        }
                    }
                }
            }
        }

        return .unknown
    }

    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - turnCount

    /// Prefer system subtype == turn_duration events (structural, accurate).
    /// Fallback to counting non-meta user messages that contain any real text
    /// (either String content or an array with at least one text block).
    /// Tool-result arrays are correctly excluded by `extractStringContent`.
    private func countUserTurns(from entries: [[String: Any]]) -> Int {
        // Try structured turn_duration events first
        let turnDurationCount = entries.filter { entry in
            entry["type"] as? String == "system" && entry["subtype"] as? String == "turn_duration"
        }.count
        if turnDurationCount > 0 { return turnDurationCount }

        return entries.filter { entry in
            guard entry["type"] as? String == "user" else { return false }
            guard entry["isMeta"] as? Bool != true else { return false }
            return extractStringContent(from: entry) != nil
        }.count
    }

    // MARK: - cwd & branch

    private func extractCwd(from entries: [[String: Any]]) -> String? {
        for entry in entries {
            if let cwd = entry["cwd"] as? String { return cwd }
        }
        return nil
    }

    private func extractBranch(from entries: [[String: Any]]) -> String? {
        // Check in reverse to get most recent branch
        for entry in entries.reversed() {
            if let branch = entry["gitBranch"] as? String { return branch }
        }
        return nil
    }

    // MARK: - Timestamps

    private func extractTimestamp(from entry: [String: Any]?) -> Date? {
        guard let entry = entry else { return nil }
        if let ts = entry["timestamp"] as? String {
            return parseISO8601(ts)
        }
        if let ts = entry["timestamp"] as? Double {
            // milliseconds
            return Date(timeIntervalSince1970: ts / 1000.0)
        }
        if let ts = entry["timestamp"] as? Int {
            return Date(timeIntervalSince1970: Double(ts) / 1000.0)
        }
        return nil
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Helpers

    /// Count lines in a file without parsing JSON — O(n) on bytes, not objects.
    private static func countLines(at path: String) -> Int {
        guard let data = FileManager.default.contents(atPath: path) else { return 0 }
        return data.reduce(0) { count, byte in count + (byte == UInt8(ascii: "\n") ? 1 : 0) }
    }

    private func truncate(_ s: String, to maxLen: Int) -> String {
        if s.count <= maxLen { return s }
        return String(s.prefix(maxLen - 1)) + "…"
    }

    // MARK: - Signal Extraction

    /// Extract structured signals from a session's JSONL for title/summary generation.
    public func extractSignals(for ref: SessionRef) async throws -> SessionSignals {
        let path = try findJSONLPath(for: ref.sessionID)
        let firstEntries = try JSONLParser.readFirstEntries(at: path, count: 10)
        let lastEntries = try JSONLParser.readLastEntries(at: path, count: 50)
        let allEntries = mergeEntries(first: firstEntries, last: lastEntries)

        var signals = SessionSignals(sessionID: ref.sessionID)
        signals.entrypoint = extractEntrypoint(from: allEntries)
        signals.branch = extractBranch(from: allEntries)
        signals.slug = extractSlug(from: allEntries)
        signals.firstUserIntent = extractFirstUserIntent(from: allEntries)
        signals.lastUserIntent = extractCurrentTaskSummary(from: allEntries)
        signals.lastAssistantProgress = extractLastCompletedProgress(from: allEntries)
        let (tools, files) = extractToolsAndFiles(from: allEntries)
        signals.toolsUsed = tools
        signals.filesModified = files
        signals.isSidechain = allEntries.contains { $0["isSidechain"] as? Bool == true }
        signals.turnCount = countUserTurns(from: allEntries)
        signals.hasAssistantReply = allEntries.contains { $0["type"] as? String == "assistant" }

        // Extract slash commands and error output for placeholder title generation
        let (cmds, errors) = extractCommandInfo(from: allEntries)
        signals.slashCommands = cmds
        signals.commandErrors = errors

        // Session scale: count lines in file (cheap, no JSON parsing)
        signals.totalEntryCount = Self.countLines(at: path)

        // v0.2.8: populate versionMentions from assembled signals (I-11)
        signals.versionMentions = VersionMentionExtractor.extract(from: signals)

        return signals
    }

    /// Extract key user + assistant text turns for LLM context.
    /// Uses head (10) + middle sample + tail (50) to avoid full file parse.
    /// Kept for callers that want the cheap (windowed) path; the LLM enhance
    /// flow uses `extractEnhanceInputs` instead, which reads the full file.
    public func extractKeyTurns(for ref: SessionRef, maxTurns: Int = 5) async throws -> [String] {
        let path = try findJSONLPath(for: ref.sessionID)
        let firstEntries = try JSONLParser.readFirstEntries(at: path, count: 10)
        let lastEntries = try JSONLParser.readLastEntries(at: path, count: 50)
        // Also grab middle samples if file is large enough
        let middleSamples = (try? JSONLParser.readSampledUserTurns(at: path, count: 5)) ?? []
        let allEntries = mergeEntries(first: firstEntries, last: lastEntries) + middleSamples

        var turns: [String] = []
        for entry in allEntries {
            guard let type = entry["type"] as? String else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }

            if type == "user" && entry["isMeta"] as? Bool != true {
                if let content = message["content"] as? String {
                    let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && !isInternalCommandNoise(cleaned) {
                        turns.append("用户: \(String(cleaned.prefix(300)))")
                    }
                }
            } else if type == "assistant" {
                if let content = message["content"] as? String {
                    turns.append("助手: \(String(content.prefix(300)))")
                } else if let contentArray = message["content"] as? [[String: Any]] {
                    for block in contentArray {
                        if block["type"] as? String == "text", let text = block["text"] as? String {
                            turns.append("助手: \(String(text.prefix(300)))")
                            break
                        }
                    }
                }
            }
        }

        // Take evenly spaced turns if more than maxTurns
        if turns.count <= maxTurns { return turns }
        var sampled: [String] = []
        let step = Double(turns.count) / Double(maxTurns)
        for i in 0..<maxTurns {
            sampled.append(turns[min(Int(Double(i) * step), turns.count - 1)])
        }
        return sampled
    }

    /// Bundled result of a single full-file pass for the LLM enhance path.
    public struct EnhanceInputs: Sendable {
        public let signals: SessionSignals
        public let rawTurns: [String]
    }

    /// Full-scan extraction used only by the LLM enhance flow.
    ///
    /// This path reads every entry of the session JSONL (unlike the cheap
    /// head-10 / tail-50 window used by `extractSignals`). It fixes three
    /// classes of silent failure seen on heavy-tool / sdk-cli sessions:
    ///
    /// - `firstUserIntent` / `lastUserIntent` no longer nil just because the
    ///   real text turns happen to sit outside the 60-entry window.
    /// - `historyDisplayTexts` is populated directly from the JSONL user
    ///   stream when the external `~/.claude/history.jsonl` has no rows for
    ///   this session (common for `entrypoint: sdk-cli`).
    /// - `rawTurns` are position-labeled `[首]` / `[中]` / `[末]` so the
    ///   system prompt's anti-tail-bias rule has concrete anchors to bind to.
    public func extractEnhanceInputs(for ref: SessionRef) async throws -> EnhanceInputs {
        let path = try findJSONLPath(for: ref.sessionID)
        let allEntries = try JSONLParser.readAllEntries(at: path)

        var signals = SessionSignals(sessionID: ref.sessionID)
        signals.entrypoint = extractEntrypoint(from: allEntries)
        signals.branch = extractBranch(from: allEntries)
        signals.slug = extractSlug(from: allEntries)
        signals.firstUserIntent = extractFirstUserIntent(from: allEntries)
        signals.lastUserIntent = extractCurrentTaskSummary(from: allEntries)
        signals.lastAssistantProgress = extractLastCompletedProgress(from: allEntries)
        let (tools, files) = extractToolsAndFiles(from: allEntries)
        signals.toolsUsed = tools
        signals.filesModified = files
        signals.isSidechain = allEntries.contains { $0["isSidechain"] as? Bool == true }
        signals.turnCount = countUserTurns(from: allEntries)
        signals.hasAssistantReply = allEntries.contains { $0["type"] as? String == "assistant" }

        let (cmds, errors) = extractCommandInfo(from: allEntries)
        signals.slashCommands = cmds
        signals.commandErrors = errors

        signals.totalEntryCount = Self.countLines(at: path)

        // Jsonl-derived user-text history — fallback source for MilestoneSampler
        // when ~/.claude/history.jsonl has no rows for this session.
        // SignalExtractor.enrich() will preserve this unless history.jsonl has content.
        let jsonlHistory = extractUserTextHistory(from: allEntries)
        signals.historyDisplayTexts = jsonlHistory
        signals.historyCount = jsonlHistory.count

        signals.versionMentions = VersionMentionExtractor.extract(from: signals)

        // Position-labeled rawTurns sampled from user text turns across the file.
        let maxTurns = signals.totalEntryCount > 100 ? 8 : 5
        let rawTurns = extractLabeledUserTurns(from: allEntries, maxTurns: maxTurns)

        return EnhanceInputs(signals: signals, rawTurns: rawTurns)
    }

    /// Collect all non-meta, non-noise user text turns in chronological order.
    /// Used both to populate `historyDisplayTexts` fallback and as the source
    /// pool for `extractLabeledUserTurns`. Accepts both String and text-block
    /// array shapes via `extractStringContent`.
    private func extractUserTextHistory(from entries: [[String: Any]]) -> [String] {
        var out: [String] = []
        for entry in entries {
            guard entry["type"] as? String == "user" else { continue }
            guard entry["isMeta"] as? Bool != true else { continue }
            guard let cleaned = extractStringContent(from: entry) else { continue }
            if cleaned.isEmpty || isInternalCommandNoise(cleaned) { continue }
            out.append(cleaned)
        }
        return out
    }

    /// Evenly sample `maxTurns` user text turns from `entries`, tagging each
    /// with a position label. Labels are based on the turn's index inside the
    /// filtered user-text stream (not on raw file line index), so 10% head and
    /// 10% tail windows stay meaningful regardless of how much tool_result
    /// noise surrounds the real turns.
    private func extractLabeledUserTurns(from entries: [[String: Any]], maxTurns: Int) -> [String] {
        // Collect qualifying turns (index inside filtered stream, text).
        var collected: [String] = []
        for entry in entries {
            guard entry["type"] as? String == "user" else { continue }
            guard entry["isMeta"] as? Bool != true else { continue }
            guard let cleaned = extractStringContent(from: entry) else { continue }
            if cleaned.isEmpty || isInternalCommandNoise(cleaned) { continue }
            collected.append(String(cleaned.prefix(300)))
        }
        if collected.isEmpty { return [] }

        // Evenly sample down to maxTurns (keep all if fewer).
        let picked: [(pos: Int, text: String)]
        if collected.count <= maxTurns {
            picked = collected.enumerated().map { ($0.offset, $0.element) }
        } else {
            let step = Double(collected.count) / Double(maxTurns)
            picked = (0..<maxTurns).map { i in
                let idx = min(Int(Double(i) * step), collected.count - 1)
                return (idx, collected[idx])
            }
        }

        // Label by position inside the filtered user-text stream.
        let total = collected.count
        let headCut = max(total / 10, 1)          // first 10% (≥1)
        let tailCut = max(total - max(total / 10, 1), 0) // last 10% (≥1)
        return picked.map { item in
            let label: String
            if item.pos < headCut {
                label = "[首]"
            } else if item.pos >= tailCut {
                label = "[末]"
            } else {
                label = "[中]"
            }
            return "\(label) 用户: \(item.text)"
        }
    }

    // MARK: - Signal Extraction Helpers

    private func extractCommandInfo(from entries: [[String: Any]]) -> (commands: [String], errors: [String]) {
        var commands: [String] = []
        var errors: [String] = []
        for entry in entries {
            guard entry["type"] as? String == "user" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            if let content = message["content"] as? String {
                // Extract <command-name>X</command-name>
                if content.contains("<command-name>"),
                   let regex = try? NSRegularExpression(pattern: "<command-name>(.*?)</command-name>"),
                   let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                   let range = Range(match.range(at: 1), in: content) {
                    commands.append(String(content[range]))
                }
                // Extract <local-command-stdout>X</local-command-stdout>
                if content.contains("<local-command-stdout>"),
                   let regex = try? NSRegularExpression(pattern: "<local-command-stdout>(.*?)</local-command-stdout>", options: .dotMatchesLineSeparators),
                   let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                   let range = Range(match.range(at: 1), in: content) {
                    let output = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !output.isEmpty { errors.append(output) }
                }
            }
        }
        return (commands, errors)
    }

    private func extractEntrypoint(from entries: [[String: Any]]) -> String? {
        for entry in entries {
            if let ep = entry["entrypoint"] as? String { return ep }
        }
        return nil
    }

    private func extractSlug(from entries: [[String: Any]]) -> String? {
        for entry in entries {
            if let slug = entry["slug"] as? String, !slug.isEmpty { return slug }
        }
        return nil
    }

    private func extractFirstUserIntent(from entries: [[String: Any]]) -> String? {
        for entry in entries {
            guard entry["type"] as? String == "user" else { continue }
            guard entry["isMeta"] as? Bool != true else { continue }
            guard let content = extractStringContent(from: entry) else { continue }
            if isInternalCommandNoise(content) { continue }
            return content
        }
        return nil
    }

    private func extractToolsAndFiles(from entries: [[String: Any]]) -> (tools: Set<String>, files: Set<String>) {
        var tools = Set<String>()
        var files = Set<String>()
        let fileTools: Set<String> = ["Edit", "Write", "MultiEdit"]

        for entry in entries {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            guard let contentArray = message["content"] as? [[String: Any]] else { continue }
            for item in contentArray {
                guard item["type"] as? String == "tool_use" else { continue }
                guard let name = item["name"] as? String else { continue }
                tools.insert(name)
                if fileTools.contains(name),
                   let input = item["input"] as? [String: Any],
                   let filePath = input["file_path"] as? String {
                    files.insert(filePath)
                }
            }
        }
        return (tools, files)
    }

    /// Extract the last completed progress from assistant messages.
    /// Looks for completion-oriented language ("完成", "done", "fixed", "已", "成功")
    /// rather than forward-looking language ("接下来", "next", "should").
    private func extractLastCompletedProgress(from entries: [[String: Any]]) -> String? {
        let completionPattern = "完成|已完成|已修改|已重构|已添加|已创建|已修复|已更新|已实现|成功|done|fixed|completed|implemented|created|updated|added|refactored|resolved"

        guard let regex = try? NSRegularExpression(pattern: completionPattern, options: .caseInsensitive) else {
            return nil
        }

        // Reverse scan assistant messages for completion statements
        for entry in entries.reversed() {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }

            if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray.reversed() {
                    guard block["type"] as? String == "text" else { continue }
                    guard let text = block["text"] as? String else { continue }
                    if let sentence = findCompletionSentence(in: text, regex: regex) {
                        return sentence
                    }
                }
            } else if let content = message["content"] as? String {
                if let sentence = findCompletionSentence(in: content, regex: regex) {
                    return sentence
                }
            }
        }
        return nil
    }

    private func findCompletionSentence(in text: String, regex: NSRegularExpression) -> String? {
        let strippedText = stripCodeBlocks(text)
        let sentenceDelimiters = CharacterSet(charactersIn: "。！？.!?\n")
        let sentences = strippedText.components(separatedBy: sentenceDelimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Find last matching sentence (most recent completion)
        var lastMatch: String? = nil
        for sentence in sentences {
            let range = NSRange(sentence.startIndex..., in: sentence)
            if regex.firstMatch(in: sentence, range: range) != nil {
                lastMatch = sentence
            }
        }

        guard let match = lastMatch else { return nil }
        if match.count <= 120 { return match }
        return String(match.prefix(119)) + "…"
    }

    // MARK: - loadSessionDetail (full JSONL scan)

    public func loadSessionDetail(for ref: SessionRef) async throws -> SessionDetail {
        // Find the JSONL file for this session
        let jsonlPath = try findJSONLPath(for: ref.sessionID)

        // Read ALL entries for full scan
        let allEntries = try JSONLParser.readAllEntries(at: jsonlPath)

        // Build summary directly from this file's data (no redundant full scan)
        let metadata = loadSessionMetadata()
        let summary = try buildSummary(from: jsonlPath, metadata: metadata)

        // 1. totalErrorCount — count ALL tool_result with is_error:true
        let totalErrorCount = countTotalErrors(from: allEntries)

        // 2. cumulativeTokens — sum ALL usage objects from assistant entries
        let cumulativeTokens = sumCumulativeTokens(from: allEntries)

        // 3. recentFiles — all unique file_path from Edit/Write/MultiEdit, last 10
        let recentFiles = extractRecentFiles(from: allEntries)

        // 4. nextStep — reverse scan for forward-looking sentence
        let nextStep = extractNextStep(from: allEntries)

        // 5. modelInfo — from latest assistant message.model
        let modelInfo = extractModelInfo(from: allEntries)

        return SessionDetail(
            summary: summary,
            totalErrorCount: totalErrorCount,
            cumulativeTokens: cumulativeTokens,
            recentFiles: recentFiles,
            nextStep: nextStep,
            modelInfo: modelInfo
        )
    }

    // MARK: - Detail Extraction Helpers

    private func findJSONLPath(for sessionID: String) throws -> String {
        let fm = FileManager.default
        let projectsDir = baseDirectory + "/projects"
        guard fm.fileExists(atPath: projectsDir) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let filename = sessionID + ".jsonl"
        if let topLevelContents = try? fm.contentsOfDirectory(atPath: projectsDir) {
            for projectDir in topLevelContents {
                let projectPath = projectsDir + "/" + projectDir
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }
                if projectDir == "memory" { continue }
                if projectPath.contains("/subagents/") { continue }
                let candidate = projectPath + "/" + filename
                if fm.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    private func countTotalErrors(from entries: [[String: Any]]) -> Int {
        var count = 0
        for entry in entries {
            guard entry["type"] as? String == "user" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            guard let contentArray = message["content"] as? [[String: Any]] else { continue }
            for item in contentArray {
                guard item["type"] as? String == "tool_result" else { continue }
                if item["is_error"] as? Bool == true {
                    count += 1
                }
            }
        }
        return count
    }

    private func sumCumulativeTokens(from entries: [[String: Any]]) -> TokenBreakdown? {
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var found = false

        for entry in entries {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            guard let usage = message["usage"] as? [String: Any] else { continue }
            found = true
            inputTokens += usage["input_tokens"] as? Int ?? 0
            outputTokens += usage["output_tokens"] as? Int ?? 0
            cacheReadTokens += usage["cache_read_input_tokens"] as? Int ?? 0
            cacheWriteTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
        }

        guard found else { return nil }
        return TokenBreakdown(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens
        )
    }

    private func extractRecentFiles(from entries: [[String: Any]]) -> [String] {
        let toolNames: Set<String> = ["Edit", "Write", "MultiEdit"]
        var orderedFiles: [String] = []
        var seen = Set<String>()

        for entry in entries {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            guard let contentArray = message["content"] as? [[String: Any]] else { continue }
            for item in contentArray {
                guard item["type"] as? String == "tool_use" else { continue }
                guard let name = item["name"] as? String, toolNames.contains(name) else { continue }
                if let input = item["input"] as? [String: Any],
                   let filePath = input["file_path"] as? String {
                    if seen.contains(filePath) {
                        // Move to end (most recent)
                        orderedFiles.removeAll { $0 == filePath }
                    } else {
                        seen.insert(filePath)
                    }
                    orderedFiles.append(filePath)
                }
            }
        }
        return Array(orderedFiles.suffix(10))
    }

    private func extractNextStep(from entries: [[String: Any]]) -> String? {
        let chinesePattern = "接下来|下一步|然后|建议|需要|可以继续|之后"
        let englishPattern = "next|then|should|let's|we can|after that|TODO"
        let combinedPattern = "\(chinesePattern)|\(englishPattern)"

        guard let regex = try? NSRegularExpression(pattern: combinedPattern, options: .caseInsensitive) else {
            return nil
        }

        // Reverse scan assistant messages
        for entry in entries.reversed() {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }

            // Handle content as array of blocks
            if let contentArray = message["content"] as? [[String: Any]] {
                // Reverse scan blocks within this entry
                for block in contentArray.reversed() {
                    guard block["type"] as? String == "text" else { continue }
                    guard let text = block["text"] as? String else { continue }
                    if let sentence = findForwardLookingSentence(in: text, regex: regex) {
                        return sentence
                    }
                }
            }
            // Handle content as plain string
            else if let content = message["content"] as? String {
                if let sentence = findForwardLookingSentence(in: content, regex: regex) {
                    return sentence
                }
            }
        }
        return nil
    }

    private func findForwardLookingSentence(in text: String, regex: NSRegularExpression) -> String? {
        // Strip fenced code blocks before searching
        let strippedText = stripCodeBlocks(text)

        // Split into sentences (handle Chinese and English punctuation)
        let sentenceDelimiters = CharacterSet(charactersIn: "。！？.!?\n")
        let sentences = strippedText.components(separatedBy: sentenceDelimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Find last matching sentence
        var lastMatch: String? = nil
        for sentence in sentences {
            let range = NSRange(sentence.startIndex..., in: sentence)
            if regex.firstMatch(in: sentence, range: range) != nil {
                lastMatch = sentence
            }
        }

        guard let match = lastMatch else { return nil }
        if match.count <= 120 { return match }
        return String(match.prefix(119)) + "…"
    }

    /// Remove fenced code blocks (```...```) and inline code (`...`) to avoid
    /// matching keywords like TODO/next/should inside code snippets.
    private func stripCodeBlocks(_ text: String) -> String {
        var result = text
        // Remove fenced code blocks (``` ... ```)
        if let fencedRegex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
            result = fencedRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove inline code (` ... `)
        if let inlineRegex = try? NSRegularExpression(pattern: "`[^`]+`", options: []) {
            result = inlineRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
    }

    private func extractModelInfo(from entries: [[String: Any]]) -> ModelInfo? {
        for entry in entries.reversed() {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            if let model = message["model"] as? String {
                return ModelInfo.resolve(modelName: model)
            }
        }
        return nil
    }

    // MARK: - makeResumeTarget

    public func makeResumeTarget(for ref: SessionRef) throws -> ResumeTarget {
        // Extract cwd on demand from JSONL (no shared mutable cache)
        var cwd: String? = nil
        if let path = try? findJSONLPath(for: ref.sessionID) {
            let entries = (try? JSONLParser.readFirstEntries(at: path, count: 3)) ?? []
            cwd = extractCwd(from: entries)
        }
        return ResumeTarget(
            executable: "claude",
            arguments: ["-r", ref.sessionID],
            workingDirectory: cwd,
            displayCommand: "claude -r \(ref.sessionID)"
        )
    }

    // MARK: - refreshRuntimeState

    /// Build a sessionID → (pid, startedAt) map from sessions/<pid>.json files.
    /// Claude stores metadata as `sessions/<pid>.json` with sessionId inside the JSON body.
    private func loadSessionMetadata() -> [String: (pid: Int32, startedAt: Date?)] {
        let fm = FileManager.default
        let sessionsDir = baseDirectory + "/sessions"
        var map: [String: (pid: Int32, startedAt: Date?)] = [:]

        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return map }
        for file in files where file.hasSuffix(".json") {
            let path = sessionsDir + "/" + file
            guard let data = fm.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int,
                  let sid = json["sessionId"] as? String else { continue }

            var startedAt: Date? = nil
            if let ts = json["startedAt"] as? Double {
                startedAt = Date(timeIntervalSince1970: ts / 1000.0)
            } else if let ts = json["startedAt"] as? Int {
                startedAt = Date(timeIntervalSince1970: Double(ts) / 1000.0)
            }
            map[sid] = (pid: Int32(pid), startedAt: startedAt)
        }
        return map
    }

    public func refreshRuntimeState(for refs: [SessionRef]) async -> [SessionRef: SessionRuntimeState] {
        let metadata = loadSessionMetadata()
        var result: [SessionRef: SessionRuntimeState] = [:]

        for ref in refs {
            if let meta = metadata[ref.sessionID] {
                let alive = kill(meta.pid, 0) == 0
                result[ref] = alive ? .alive(pid: meta.pid) : .dead
            } else {
                result[ref] = .dead // no metadata → assumed stopped
            }
        }

        return result
    }
}
