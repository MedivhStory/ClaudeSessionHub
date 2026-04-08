import Foundation

/// Prompt templates for LLM-powered session understanding.
/// Consumes structured SessionSignals, not raw JSONL.
public enum LLMPrompts {

    /// Build the user message for LLM from SessionSignals.
    public static func titleInput(from signals: SessionSignals, rawTurns: [String] = []) -> String {
        var parts: [String] = []

        parts.append("Session ID: \(signals.sessionID)")

        // Session scale — tells LLM how big this session is
        if signals.totalEntryCount > 0 { parts.append("总条目数: \(signals.totalEntryCount)") }
        if signals.historyCount > 0 { parts.append("用户输入次数: \(signals.historyCount)") }

        if let ep = signals.entrypoint { parts.append("启动方式: \(ep)") }
        if let branch = signals.branch { parts.append("分支: \(branch)") }
        if signals.turnCount > 0 { parts.append("对话轮次: \(signals.turnCount)") }
        if !signals.filesModified.isEmpty {
            parts.append("修改文件: \(signals.filesModified.prefix(5).joined(separator: ", "))")
        }
        if !signals.toolsUsed.isEmpty {
            parts.append("使用工具: \(signals.toolsUsed.sorted().joined(separator: ", "))")
        }

        if let intent = signals.firstUserIntent {
            parts.append("用户首轮意图: \(String(intent.prefix(200)))")
        }
        if let last = signals.lastUserIntent, last != signals.firstUserIntent {
            parts.append("用户最近意图: \(String(last.prefix(200)))")
        }
        if let progress = signals.lastAssistantProgress {
            parts.append("最近完成: \(String(progress.prefix(200)))")
        }
        if let subject = signals.taskSubject {
            parts.append("任务主题: \(subject)")
            if let status = signals.taskStatus { parts.append("任务状态: \(status)") }
        }

        if !signals.historyDisplayTexts.isEmpty {
            let all = signals.historyDisplayTexts

            // Extract milestone entries first (version numbers, key decisions)
            let milestoneKeywords = ["v0.", "v1.", "v2.", "版本", "封版", "brainstorm", "plan",
                                     "tag", "release", "开始", "完成", "准备"]
            let milestones = all.enumerated().filter { (_, text) in
                let lower = text.lowercased()
                return milestoneKeywords.contains(where: { lower.contains($0) })
            }.prefix(5).map { (i, text) in "[\(i+1)/\(all.count)] \(String(text.prefix(100)))" }

            // Head + tail for context
            let head = all.prefix(2).map { String($0.prefix(100)) }
            let tail = all.count > 4
                ? all.suffix(2).map { String($0.prefix(100)) }
                : []

            var historyLines: [String] = []
            historyLines.append(contentsOf: head)
            if !milestones.isEmpty {
                historyLines.append("--- 关键里程碑 ---")
                historyLines.append(contentsOf: milestones)
            }
            if !tail.isEmpty {
                historyLines.append("--- 最近 ---")
                historyLines.append(contentsOf: tail)
            }
            parts.append("用户输入历史（\(all.count) 条，从早到晚）:\n\(historyLines.joined(separator: "\n"))")
        }

        if !rawTurns.isEmpty {
            // Pass all rawTurns provided by caller (already sampled upstream).
            // Do NOT re-truncate here — the caller controls the count.
            let turnsSnippet = rawTurns
                .map { String($0.prefix(300)) }.joined(separator: "\n---\n")
            parts.append("关键对话片段（\(rawTurns.count) 条）:\n\(turnsSnippet)")
        }

        return parts.joined(separator: "\n")
    }

    public static let titleSystemPrompt = """
    你是一个 session 标题生成器。根据以下 session 信息，生成一个简短、准确的中文任务标题。

    要求：
    - 最多 30 个字
    - 描述这个 session 的核心任务或主题，不是最近的某个小操作
    - 如果 session 很长（总条目数很大），标题要概括整体方向，不要只反映最后一步
    - 如果用户输入中出现软件版本号（如 v0.2.0、v0.2.5、v1.0），标题必须包含该版本号
    - 如果 session 跨越多个版本（如从 v0.2.0 到 v0.2.5），标题应体现版本范围
    - 用任务描述的口吻，如"Claude Session Hub v0.2.0-v0.2.5 开发"、"修复登录超时问题"
    - 不要加引号、标点、编号
    - 如果信息不足，返回最合理的概括

    只返回标题文本，不要解释。
    """

    public static let progressSystemPrompt = """
    你是一个 session 进展摘要生成器。根据以下 session 信息，用一句话描述最近完成了什么。

    要求：
    - 最多 60 个字
    - 回答"最近刚完成了什么"，不是"接下来要做什么"
    - 用完成时态，如"完成了 auth middleware 的 protocol 化重构"
    - 如果没有明确完成的事项，返回空字符串

    只返回进展描述，不要解释。返回空字符串表示无明确进展。
    """

    public static let summarySystemPrompt = """
    你是一个 session 摘要生成器。根据以下 session 信息，生成 2-3 句话的摘要。

    要求：
    - 最多 150 个字
    - 第一句：这个 session 的整体目标是什么（如果涉及版本开发，需提到版本号）
    - 第二句：目前进展到哪了
    - 第三句（可选）：有什么遗留或下一步
    - 如果 session 很长，要概括整体脉络，特别关注"关键里程碑"中的版本转折点
    - 不要只描述最后一步
    - 用客观描述口吻

    只返回摘要文本，不要解释。
    """
}
