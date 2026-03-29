import Foundation
#if canImport(Darwin)
import Darwin
#endif

public final class ClaudeProvider: AgentProvider, @unchecked Sendable {
    public let id: ProviderID = "claude"
    public let displayName = "Claude Code"
    public let capabilities: ProviderCapabilities = [.resume, .contextUsage, .errorTracking, .branchInfo]

    private let baseDirectory: String
    /// Cache of discovered sessions for cwd lookup
    private var discoveredCwds: [String: String] = [:]

    public init(baseDirectory: String? = nil) {
        self.baseDirectory = baseDirectory ?? (NSHomeDirectory() + "/.claude")
    }

    // MARK: - discoverSessions

    public func discoverSessions() async throws -> [SessionSummary] {
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
            if let summary = try? buildSummary(from: path) {
                summaries.append(summary)
            }
        }
        return summaries
    }

    // MARK: - Build Summary

    private func buildSummary(from path: String) throws -> SessionSummary {
        let firstEntries = try JSONLParser.readFirstEntries(at: path, count: 10)
        let lastEntries = try JSONLParser.readLastEntries(at: path, count: 10)
        let allEntries = mergeEntries(first: firstEntries, last: lastEntries)

        // Session ID from filename
        let filename = (path as NSString).lastPathComponent
        let sessionID = String(filename.dropLast(6)) // remove .jsonl

        let ref = SessionRef(providerID: id, sessionID: sessionID)

        // Extract cwd from entries
        let cwd = extractCwd(from: allEntries)
        if let cwd = cwd {
            discoveredCwds[sessionID] = cwd
        }

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

        // recentErrorCount
        let recentErrorCount = extractRecentErrorCount(from: allEntries)

        // taskPhase
        let taskPhase = extractTaskPhase(from: allEntries)

        // turnCount
        let turnCount = countUserTurns(from: allEntries)

        // timestamps
        let createdAt = extractTimestamp(from: firstEntries.first) ?? Date()
        let lastActiveAt = extractTimestamp(from: lastEntries.last) ?? Date()

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
            contextUsage: contextUsage
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
        let englishPattern = "^(fix|add|create|build|implement|refactor|debug|update|remove|setup|configure|write|test|review|check|run)\\b"

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
        // content can be a String or an Array
        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Reverse scan for last user entry that is not meta and has plain String content
        for entry in entries.reversed() {
            guard entry["type"] as? String == "user" else { continue }
            guard entry["isMeta"] as? Bool != true else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
            // Must be plain string content, not array (tool_result)
            guard let content = message["content"] as? String else { continue }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            return truncate(trimmed, to: 80)
        }
        return nil
    }

    // MARK: - contextUsage

    private func extractContextUsage(from entries: [[String: Any]]) -> ContextUsage? {
        // Find last assistant entry with message.usage
        for entry in entries.reversed() {
            guard entry["type"] as? String == "assistant" else { continue }
            guard let message = entry["message"] as? [String: Any] else { continue }
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

    private func extractRecentErrorCount(from entries: [[String: Any]]) -> Int {
        var count = 0
        for entry in entries {
            // tool_result entries appear as user-type messages
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

    private func countUserTurns(from entries: [[String: Any]]) -> Int {
        return entries.filter { entry in
            entry["type"] as? String == "user" && entry["isMeta"] as? Bool != true
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

    private func truncate(_ s: String, to maxLen: Int) -> String {
        if s.count <= maxLen { return s }
        return String(s.prefix(maxLen - 1)) + "…"
    }

    // MARK: - loadSessionDetail (minimal for Task 3)

    public func loadSessionDetail(for ref: SessionRef) async throws -> SessionDetail {
        // Minimal: discover and find the matching summary
        let sessions = try await discoverSessions()
        guard let summary = sessions.first(where: { $0.ref == ref }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return SessionDetail(
            summary: summary,
            totalErrorCount: summary.recentErrorCount,
            cumulativeTokens: nil,
            recentFiles: [],
            nextStep: nil,
            modelInfo: nil
        )
    }

    // MARK: - makeResumeTarget

    public func makeResumeTarget(for ref: SessionRef) throws -> ResumeTarget {
        let cwd = discoveredCwds[ref.sessionID]
        return ResumeTarget(
            executable: "claude",
            arguments: ["-r", ref.sessionID],
            workingDirectory: cwd,
            displayCommand: "claude -r \(ref.sessionID)"
        )
    }

    // MARK: - refreshRuntimeState

    public func refreshRuntimeState(for refs: [SessionRef]) async -> [SessionRef: SessionRuntimeState] {
        let fm = FileManager.default
        let sessionsDir = baseDirectory + "/sessions"
        var result: [SessionRef: SessionRuntimeState] = [:]

        for ref in refs {
            let metadataPath = sessionsDir + "/\(ref.sessionID).json"
            guard fm.fileExists(atPath: metadataPath),
                  let data = fm.contents(atPath: metadataPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int32 else {
                result[ref] = .dead
                continue
            }

            let alive = kill(pid, 0) == 0
            result[ref] = alive ? .alive(pid: pid) : .dead
        }

        return result
    }
}
