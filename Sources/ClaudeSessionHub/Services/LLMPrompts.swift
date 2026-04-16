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

        // v0.2.8: Structured version mention injection (I-14: zero-detection covers all 3 fields)
        if !signals.versionMentions.isEmpty {
            parts.append("识别到的版本号（有限列表，请严格依据）:")
            for vm in signals.versionMentions {
                let loc = renderSourceRef(vm.selectedSource)
                parts.append("  - \(vm.raw) → normalized=\(vm.normalized), 出现 \(vm.occurrenceCount) 次, selectedSource: \(loc)")
            }
        } else {
            parts.append("本 session 未识别到任何版本号。")
        }

        // v0.2.8: MilestoneSampler replaces inline keyword filter
        if !signals.historyDisplayTexts.isEmpty {
            let K = MilestoneSampler.adaptiveK(
                historyCount: signals.historyDisplayTexts.count
            )
            let milestones = MilestoneSampler.sample(
                history: signals.historyDisplayTexts,
                versionMentions: signals.versionMentions,
                K: K
            )
            parts.append("用户输入历史（\(signals.historyDisplayTexts.count) 条，选取 \(milestones.count) 个关键里程碑）:")
            for m in milestones {
                let label = renderMilestoneLabel(m.reasons)
                parts.append("  \(label) \(String(m.text.prefix(100)))")
            }
        }

        if !rawTurns.isEmpty {
            // Pass all rawTurns provided by caller (already sampled + position-labeled upstream).
            // Labels [首] / [中] / [末] signal position inside the filtered user-text stream,
            // so the anti-tail-bias rule in the system prompt can bind to concrete anchors
            // even when historyDisplayTexts milestones are absent (sdk-cli sessions etc.).
            // Do NOT re-truncate here — the caller controls the count.
            let turnsSnippet = rawTurns
                .map { String($0.prefix(300)) }.joined(separator: "\n---\n")
            parts.append("关键对话片段（\(rawTurns.count) 条，带位置标签 [首]/[中]/[末]）:\n\(turnsSnippet)")
        }

        return parts.joined(separator: "\n")
    }

    private static let baseTitleSystemPrompt = """
    你是一个 session 标题生成器。根据以下 session 信息，生成一个简短、准确的中文任务标题。

    要求：
    - **严格不超过 30 个字**（含标点）；如果超出，删减后再返回
    - **标题必须反映 session 的主线 arc，不得仅反映最后几轮对话的局部主题**
    - 判断主线 arc 时：优先参考 [首条]、[版本锚点] 标记的 milestone 条目，以及"关键对话片段"中带 [首] / [中] 位置标签的条目——它们代表整个会话的脉络；[末条] 与 [末] 标签代表会话当前结束点，通常只是阶段性动作，不应主导标题
    - 如果 session 很长（总条目数 > 100 或轮次 > 100），标题**必须**概括整体方向，反例：session 讨论了 v0.2.5 到 v0.2.8 的开发收尾，不应写"更新 Xcode CI 文档"（那只是最后一步），应写"v0.2.x 系列开发收尾"或"Claude Session Hub v0.2 版本交接"
    - **优先使用反映主线 arc 的抽象级别表述，不要枚举具体子任务；如果一个 session 涉及多个子任务，用一个更高层的主题概括它们，而不是罗列**
      好示例：
      - 「v0.2.x 系列版本开发收尾与交接」（反映主线 arc，抽象程度够高，22 字）
      坏示例：
      - 「重构 auth 中间件 + 更新 handoff 文档 + 修改 CI 约束 + 准备 v0.2.8 发版」（枚举多个 subtask，长度爆炸，失去焦点）
    - 用任务描述的口吻，如"修复登录超时问题"
    - 不要加引号、标点、编号
    - 如果信息不足，返回最合理的概括

    只返回标题文本，不要解释。
    """

    private static let baseProgressSystemPrompt = """
    你是一个 session 进展摘要生成器。根据以下 session 信息，用一句话描述最近完成了什么。

    要求：
    - 最多 60 个字
    - 回答"最近刚完成了什么"，不是"接下来要做什么"
    - 用完成时态，如"完成了 auth middleware 的 protocol 化重构"
    - 如果没有明确完成的事项，返回空字符串

    只返回进展描述，不要解释。返回空字符串表示无明确进展。
    """

    private static let baseSummarySystemPrompt = """
    你是一个 session 摘要生成器。根据以下 session 信息，生成 2-3 句话的摘要。

    要求：
    - **严格不超过 150 个字**（含标点）；如果超出，删减后再返回
    - 第一句：这个 session 的整体目标是什么
    - 第二句：目前进展到哪了
    - 第三句（可选）：有什么遗留或下一步
    - 如果 session 很长，要概括整体脉络，不要只描述最后一步
    - 用客观描述口吻

    只返回摘要文本，不要解释。
    """

    private static let versionClauseShared = """

    【版本号约束】
    - 如果上面的 input 里提供了"识别到的版本号"列表：仅当某版本号**出现次数 ≥ 2 次**，或其 **selectedSource 属于 taskSubject / firstUserIntent / taskDescription 之一**时，才应在输出中引用它
    - 满足上述条件的版本号，若是主题型版本（即该 session 是在开发该版本），应在输出中体现；若 session 跨越多个满足条件的版本号，应在输出中体现版本范围（例如 "v0.2.5-v0.2.6" 或 "v0.2.5 到 v0.2.6"）
    - 如果版本号仅出现 1 次，且 selectedSource 属于 lastUserIntent / history / lastAssistantProgress 之一，属于顺带提及：**绝对禁止**在 title / progress / summary 任何一个字段中引用它。这条规则对 summary 字段尤为严格——即使在描述"向后兼容"、"适配旧接口"等场景时，也绝对不得在 summary 里写出该版本号。正确做法：用抽象描述（如"保持向后兼容"）代替具体版本号。错误示例（禁止）："适配 v0.2.0 的旧接口"；正确示例（允许）："适配旧接口以保持向后兼容"
    - 如果上面的 input 里"本 session 未识别到任何版本号"：**禁止**在输出（title / progress / summary 任一字段）中引入任何版本号、版本范围、版本类语言。不要虚构、不要从语境推断、不要使用类似 "新版本"、"v1.0" 的占位表达
    """

    public static let titleSystemPrompt = baseTitleSystemPrompt + versionClauseShared
    public static let progressSystemPrompt = baseProgressSystemPrompt + versionClauseShared
    public static let summarySystemPrompt = baseSummarySystemPrompt + versionClauseShared

    private static func renderMilestoneLabel(_ reasons: [MilestoneEntry.Reason]) -> String {
        let pieces: [String] = reasons.map { reason in
            switch reason {
            case .firstEntry:
                return "首条"
            case .lastEntry:
                return "末条"
            case .versionAnchor(let normalized):
                return "版本锚点 \(normalized)"
            case .timeFill(let bucket, let total):
                return "时间补点 \(bucket + 1)/\(total)"
            }
        }
        return "[" + pieces.joined(separator: " | ") + "]"
    }

    private static func renderSourceRef(_ ref: SourceRef) -> String {
        switch ref.kind {
        case .history:
            return "history[\(ref.index ?? -1)]"
        default:
            return ref.kind.rawValue
        }
    }
}
