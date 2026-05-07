import Foundation

/// Pure functional composer for the v0.2.9 P4 evidence panel.
///
/// Maps a `SessionSummary` (+ relations) into an `EvidencePackage` whose
/// ordering matches PLAN-v0.2.9.md §9 minus the omitted `recentToolOps`
/// category. No I/O, no LLM, no async — composition is fully
/// deterministic given the same inputs.
///
/// Per `docs/PLAN-v0.2.9-P4.md` C0 audit (PM ratified):
/// - **Source 1** `recentFiles` is **degraded** to a `filesTouched`
///   count line; PLAN's `SessionDetail.recentFiles` list is async-only.
/// - **Source 2** `recentToolOps` is **omitted** (no enum case); no sync
///   read path exists for `SessionSignals.toolsUsed`.
/// - **Source 8** `latestProgress` is bound to the sync-persisted
///   `SessionSummary.lastProgress` with a fallback cascade to
///   `currentTaskSummary` (more permissive coverage on sessions where
///   only the rule-layer summary is populated).
///
/// Time anchors include `createdAt` + `lastActiveAt` only. PLAN §9 also
/// names "milestone events"; including them would require extending this
/// signature with `[MilestoneEntry]` from the caller (computed via
/// `MilestoneSampler.sample(...)` over `cachedHistoryTexts(for:)`). C1
/// stays on the rev.3 literal signature `(session:relations:)`; milestone
/// integration is a follow-up that can extend this signature without
/// breaking callers (parameter would default to `[]`).
public enum EvidenceComposer {
    public static func compose(
        session: SessionSummary,
        relations: [SessionRelation]
    ) -> EvidencePackage {
        var items: [EvidenceItem] = []

        if let item = composeRecentFiles(session: session)       { items.append(item) }
        if let item = composeTimeAnchors(session: session)       { items.append(item) }
        if let item = composeBranchCwd(session: session)         { items.append(item) }
        if let item = composeRelatedSessions(relations: relations) { items.append(item) }
        if let item = composeProjectName(session: session)       { items.append(item) }
        if let item = composeCurrentPhase(session: session)      { items.append(item) }
        if let item = composeLatestProgress(session: session)    { items.append(item) }

        return EvidencePackage(items: items)
    }

    // MARK: - Per-category composition

    private static func composeRecentFiles(session: SessionSummary) -> EvidenceItem? {
        guard session.filesTouched > 0 else { return nil }
        return EvidenceItem(
            category: .recentFiles,
            title: "最近文件",
            lines: ["\(session.filesTouched) 个文件被修改"]
        )
    }

    private static func composeTimeAnchors(session: SessionSummary) -> EvidenceItem? {
        let lines = [
            "创建于 \(session.createdAt.relativeFormatted)",
            "最近活跃 \(session.lastActiveAt.relativeFormatted)"
        ]
        return EvidenceItem(category: .timeAnchors, title: "时间锚", lines: lines)
    }

    private static func composeBranchCwd(session: SessionSummary) -> EvidenceItem? {
        var lines: [String] = []
        if let cwd = session.cwd, !cwd.isEmpty {
            lines.append("路径 · \(cwd)")
        }
        if let branch = session.branch, !branch.isEmpty {
            lines.append("分支 · \(branch)")
        }
        guard !lines.isEmpty else { return nil }
        return EvidenceItem(category: .branchCwd, title: "代码位置", lines: lines)
    }

    private static func composeRelatedSessions(relations: [SessionRelation]) -> EvidenceItem? {
        guard !relations.isEmpty else { return nil }
        let lines = relations.map { rel in
            "\(rel.otherSessionID.prefix(8)) · \(localizedRelationType(rel.type))"
        }
        return EvidenceItem(category: .relatedSessions, title: "相关会话", lines: lines)
    }

    private static func composeProjectName(session: SessionSummary) -> EvidenceItem? {
        guard let cwd = session.cwd, !cwd.isEmpty else { return nil }
        let name = ProjectNameResolver.displayName(for: cwd)
        guard !name.isEmpty else { return nil }
        return EvidenceItem(category: .projectName, title: "项目", lines: [name])
    }

    private static func composeCurrentPhase(session: SessionSummary) -> EvidenceItem? {
        switch session.taskPhase {
        case .unknown:
            return nil
        case .inProgress, .blocked, .done:
            return EvidenceItem(
                category: .currentPhase,
                title: "当前阶段",
                lines: [localizedPhase(session.taskPhase)]
            )
        }
    }

    private static func composeLatestProgress(session: SessionSummary) -> EvidenceItem? {
        // Cascade: lastProgress (sync-persisted alias for §9's
        // lastAssistantProgress) → currentTaskSummary fallback.
        if let p = session.lastProgress, !p.isEmpty {
            return EvidenceItem(category: .latestProgress, title: "最近进展", lines: [p])
        }
        if let s = session.currentTaskSummary, !s.isEmpty {
            return EvidenceItem(category: .latestProgress, title: "最近进展", lines: [s])
        }
        return nil
    }

    // MARK: - Helpers

    private static func localizedRelationType(_ type: SessionRelation.RelationType) -> String {
        switch type {
        case .sameBranch:   return "同分支"
        case .timeOverlap:  return "时间重叠"
        case .continuation: return "延续"
        }
    }

    private static func localizedPhase(_ phase: TaskPhase) -> String {
        switch phase {
        case .inProgress: return "进行中"
        case .blocked:    return "阻塞"
        case .done:       return "完成"
        case .unknown:    return ""  // unreachable — composeCurrentPhase guards
        }
    }
}
