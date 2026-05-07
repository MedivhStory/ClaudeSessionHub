import SwiftUI

struct SessionTileView: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary
    var searchQuery: String = ""
    @State private var isExpanded = false
    @State private var isEditingLabel = false
    @State private var editText = ""

    // MARK: - Computed Properties

    /// Title resolved through v0.2.9 display policy:
    /// Manual(v2) > AI(v2) > Legacy > Rule > UUID prefix.
    private var resolvedTitleField: ResolvedField {
        store.resolvedTitle(for: session.ref)
    }

    private var displayTitle: String {
        resolvedTitleField.value ?? String(session.ref.sessionID.prefix(8))
    }

    /// The Chinese chip label for the title's resolved source, or nil
    /// when no chip should be shown (`.uuidPrefix` / `.none`).
    private var titleSource: String? {
        SourceChip.label(for: resolvedTitleField.source)
    }

    private var bestSummary: String? {
        // Prefer AI/Legacy summary (first sentence), then progress.
        let summaryRes = store.resolvedSummary(for: session.ref)
        if let raw = summaryRes.value, !raw.isEmpty {
            let first = raw.components(separatedBy: CharacterSet(charactersIn: "。.！!？?\n"))
                .first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s = first, !s.isEmpty { return s }
        }
        let progressRes = store.resolvedProgress(for: session.ref)
        if let p = progressRes.value, !p.isEmpty { return p }
        return nil
    }

    private var userNote: String? {
        store.titleStore.userNote(for: session.ref.sessionID)
    }

    private var searchEvidence: [SearchScorer.MatchEvidence] {
        guard !searchQuery.isEmpty else { return [] }
        let sid = session.ref.sessionID
        return SearchScorer.matchEvidence(
            query: searchQuery, title: session.title,
            smartTitle: store.titleStore.currentTitle(for: sid)?.text,
            taskSummary: session.currentTaskSummary,
            progress: store.titleStore.lastProgress(for: sid),
            userNote: store.titleStore.userNote(for: sid),
            branch: session.branch, cwd: session.cwd, sessionID: sid,
            historyTexts: store.cachedHistoryTexts(for: sid)
        )
    }

    private func commitNoteEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        store.titleStore.setUserNote(for: session.ref.sessionID, note: trimmed.isEmpty ? nil : trimmed)
        store.labelStore.setLabel(for: session.ref, label: trimmed.isEmpty ? nil : trimmed)
        isEditingLabel = false
    }

    private var signals: [HealthSignal] { HealthEngine.computeSignals(for: session) }

    private var borderColor: Color {
        for signal in signals {
            switch signal {
            case .stale: return .orange
            case .contextNearFull, .recentErrors: return .red
            }
        }
        return .clear
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedContent
            if !searchEvidence.isEmpty { searchEvidenceRow }
            metadataRow
            if isExpanded { expandedContent }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionTile_\(session.ref.sessionID)")
        .accessibilityAction(named: isExpanded ? "折叠" : "展开详情") {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
        .contextMenu {
            Button("编辑备注") {
                editText = store.titleStore.userNote(for: session.ref.sessionID) ?? ""
                isEditingLabel = true
            }
            if store.titleStore.currentTitle(for: session.ref.sessionID) != nil {
                Button("查看标题历史") { isExpanded = true }
            }
        }
    }

    // MARK: - Collapsed Content

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Line 1: title (left) + action buttons (right end)
            HStack(spacing: 6) {
                Circle()
                    .fill(session.runtimeState == .active ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                Text(displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("tileTitle_\(session.ref.sessionID)")

                if let source = titleSource {
                    let color = SourceChip.color(for: resolvedTitleField.source)
                    Text(source)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .accessibilityIdentifier("sourceBadge_\(session.ref.sessionID)")
                        .help(resolvedTitleField.source == .legacy ? "Pre-v0.2.9 baseline" : source)
                }

                BadgeView.agent(session.ref.providerID)
                BadgeView.runtimeState(session.runtimeState)
                if let phaseBadge = BadgeView.taskPhase(session.taskPhase) { phaseBadge }

                Spacer(minLength: 8)

                // Action buttons at title line right end
                HStack(spacing: 6) {
                    Button {
                        Task { await store.refreshTitle(for: session.ref) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("刷新智能标题")

                    if session.runtimeState == .stopped { resumeButton }
                }
            }

            // Line 2: summary (left) + stats with time (right) — one line
            HStack(alignment: .center, spacing: 8) {
                if let summary = bestSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Stats + context + time — all one line, right-aligned
                HStack(spacing: 5) {
                    let dateStr = session.createdAt.formatted(date: .abbreviated, time: .omitted)
                    Text("\(dateStr) · \(session.turnCount)轮")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    if let usage = session.contextUsage {
                        Text("·").foregroundStyle(.quaternary)
                        ProgressView(value: usage.percentage)
                            .tint(contextBarColor(usage.percentage))
                            .frame(width: 50)
                        let usedK = usage.promptContext / 1000
                        let limitM = usage.limit / 1_000_000
                        Text("\(usedK)k/\(limitM > 0 ? "\(limitM)M" : "\(usage.limit / 1000)k")")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Text("·").foregroundStyle(.quaternary)
                    Text(session.lastActiveAt.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            // Line 2: user note
            if isEditingLabel {
                noteEditor
            } else if let note = userNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .padding(.leading, 16)
                    .accessibilityIdentifier("tileNote_\(session.ref.sessionID)")
            }

            // Line 3: health signals (elastic)
            if !signals.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(signals.map(signalText).joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                .padding(.leading, 16)
            }
        }
    }

    // MARK: - Note Editor

    private var noteEditor: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            TextField("输入备注…", text: $editText, onCommit: { commitNoteEdit() })
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .onExitCommand { commitNoteEdit() }
                .accessibilityIdentifier("tileLabel_\(session.ref.sessionID)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.blue.opacity(0.25), lineWidth: 1))
        .padding(.leading, 16)
    }

    // MARK: - Search Evidence

    private var searchEvidenceRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
            Text(searchEvidence.map { "[\($0.field)] \($0.snippet)" }.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(.purple)
                .lineLimit(1)
        }
        .padding(.leading, 16)
        .padding(.top, 2)
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let cwd = session.cwd {
                let cwdStatus = TerminalLauncher.cwdStatus(for: ResumeTarget(
                    executable: "", arguments: [], workingDirectory: cwd, displayCommand: ""
                ))
                switch cwdStatus {
                case .exists: metaItem(ProjectNameResolver.displayName(for: cwd))
                case .missing:
                    HStack(spacing: 2) {
                        metaItem(ProjectNameResolver.displayName(for: cwd))
                        Text("(目录不存在)")
                    }.foregroundStyle(.secondary).italic()
                case .unknown: EmptyView()
                }
            }
            if let branch = session.branch {
                metaSeparator; metaItem(branch, icon: "arrow.triangle.branch")
            }
            metaSeparator; metaItem("\(session.turnCount) turns")
            metaSeparator; metaItem("\(session.filesTouched) files")
            metaSeparator; sessionIdView
            let relCount = store.relations(for: session.ref).count
            if relCount > 0 { metaSeparator; metaItem("\(relCount) related", icon: "link") }
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .padding(.top, 5)
        .accessibilityIdentifier("tileMeta_\(session.ref.sessionID)")
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 6)
            HStack(alignment: .top, spacing: 16) {
                leftColumn.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    LLMPanelView(session: session)
                    EvidencePanel(session: session)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            let titleHistory = store.titleStore.titleHistory(for: session.ref.sessionID)
            if titleHistory.count > 1 {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("标题历史").font(.system(size: 11)).foregroundStyle(.tertiary)
                    ForEach(titleHistory.indices, id: \.self) { i in
                        Text(titleHistory[i].text)
                            .font(.system(size: 11))
                            .foregroundStyle(i == titleHistory.count - 1 ? .primary : .tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Left Column (no more stats/context — moved to collapsed)

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let smart = store.titleStore.currentTitle(for: session.ref.sessionID) {
                labeledText("规则标题:", smart.text)
            }
            if let progress = store.titleStore.lastProgress(for: session.ref.sessionID), !progress.isEmpty {
                labeledText("规则进展:", progress)
                    .accessibilityIdentifier("tileProgress_\(session.ref.sessionID)")
            }

            let relations = store.relations(for: session.ref)
            if !relations.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("关联: \(relations.count) related")
                        .font(.system(size: 12)).foregroundStyle(.blue)
                    ForEach(relations, id: \.otherSessionID) { rel in
                        HStack(spacing: 4) {
                            Text(rel.type == .sameBranch ? "同分支" : "延续")
                                .font(.system(size: 11)).foregroundStyle(.blue)
                            Text(String(rel.otherSessionID.prefix(8)))
                                .font(.system(size: 11).monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                labeledText("原始标题:", session.title, lineLimit: 2)
                HStack(spacing: 4) {
                    Text("Session ID:").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text(session.ref.sessionID)
                        .font(.system(size: 11).monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .accessibilityIdentifier("tileRawInfo_\(session.ref.sessionID)")

            // QuickFacts without stats/context (those are now in collapsed tile)
            QuickFactsView(session: session)
        }
    }

    // MARK: - Helpers

    private func labeledText(_ label: String, _ value: String, lineLimit: Int = 2) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(lineLimit)
        }
    }

    private var resumeButton: some View {
        Button {
            Task {
                if let target = await store.makeResumeTarget(for: session.ref) {
                    TerminalLauncher.launch(target: target, in: store.selectedTerminal)
                }
            }
        } label: {
            Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("resumeButton_\(session.ref.sessionID)")
        .help("Resume session")
    }

    private var sessionIdView: some View {
        Text(String(session.ref.sessionID.prefix(8)))
            .onTapGesture { TerminalLauncher.copyToClipboard(session.ref.sessionID) }
            .help("Click to copy full session ID")
    }

    private func metaItem(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 2) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text)
        }
    }

    private var metaSeparator: some View { Text("·").foregroundStyle(.quaternary) }

    private func contextBarColor(_ percentage: Double) -> Color {
        if percentage >= 0.9 { return .red }
        if percentage >= 0.75 { return .orange }
        return .green
    }

    private func signalText(_ signal: HealthSignal) -> String {
        switch signal {
        case .stale(let days): return "Stale \(days)d"
        case .contextNearFull(let pct, _, _): return "Context \(Int(pct * 100))%"
        case .recentErrors(let count): return "\(count) error\(count == 1 ? "" : "s")"
        }
    }

    // relativeTime moved to Date.relativeFormatted extension
}
