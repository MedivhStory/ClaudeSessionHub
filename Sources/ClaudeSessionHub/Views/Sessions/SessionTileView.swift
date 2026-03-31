import SwiftUI

struct SessionTileView: View {
    @Environment(SessionStore.self) var store
    let session: SessionSummary
    @State private var isExpanded = false
    @State private var isEditingLabel = false
    @State private var editText = ""

    private var displayTitle: String {
        store.labelStore.label(for: session.ref) ?? session.title
    }

    private var signals: [HealthSignal] {
        HealthEngine.computeSignals(for: session)
    }

    private var borderColor: Color {
        for signal in signals {
            switch signal {
            case .stale:
                return .orange
            case .contextNearFull, .recentErrors:
                return .red
            }
        }
        return Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Layer 1: Status dot, title, badges, time, resume
            layer1

            // Layer 2: Task summary + signals
            layer2

            // Layer 3: Metadata
            layer3

            // Expanded: QuickFacts
            if isExpanded {
                Divider()
                    .padding(.vertical, 4)
                QuickFactsView(session: session)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionTile_\(session.ref.sessionID)")
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Layer 1

    private var layer1: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.runtimeState == .active ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            if isEditingLabel {
                TextField("Label", text: $editText, onCommit: {
                    let trimmed = editText.trimmingCharacters(in: .whitespaces)
                    store.labelStore.setLabel(for: session.ref, label: trimmed.isEmpty ? nil : trimmed)
                    isEditingLabel = false
                })
                .font(.headline)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("tileLabel_\(session.ref.sessionID)")
            } else {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("tileTitle_\(session.ref.sessionID)")
                    .onTapGesture(count: 2) {
                        editText = displayTitle
                        isEditingLabel = true
                    }
            }

            BadgeView.agent(session.ref.providerID)
            BadgeView.runtimeState(session.runtimeState)

            if let phaseBadge = BadgeView.taskPhase(session.taskPhase) {
                phaseBadge
            }

            Spacer()

            Text(relativeTime(session.lastActiveAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            if session.runtimeState == .stopped {
                resumeButton
            }
        }
    }

    // MARK: - Layer 2

    private var layer2: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let summary = session.currentTaskSummary, !summary.isEmpty {
                HStack(spacing: 0) {
                    Text("  ")
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("tileSummary_\(session.ref.sessionID)")
                }
            }

            if !signals.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(signals.map(signalText).joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.leading, 14)
            }
        }
    }

    // MARK: - Layer 3

    private var layer3: some View {
        HStack(spacing: 6) {
            if let cwd = session.cwd {
                let cwdStatus = TerminalLauncher.cwdStatus(for: ResumeTarget(
                    executable: "", arguments: [], workingDirectory: cwd, displayCommand: ""
                ))
                switch cwdStatus {
                case .exists:
                    metaItem(ProjectNameResolver.displayName(for: cwd))
                case .missing:
                    HStack(spacing: 2) {
                        metaItem(ProjectNameResolver.displayName(for: cwd))
                        Text("(目录不存在)")
                    }
                    .foregroundStyle(.secondary)
                    .italic()
                case .unknown:
                    EmptyView()
                }
            }

            if let branch = session.branch {
                metaSeparator
                metaItem(branch, icon: "arrow.triangle.branch")
            }

            metaSeparator
            metaItem("\(session.turnCount) turns")

            metaSeparator
            metaItem("\(session.filesTouched) files")

            metaSeparator
            sessionIdView
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
        .accessibilityIdentifier("tileMeta_\(session.ref.sessionID)")
    }

    // MARK: - Helpers

    private var resumeButton: some View {
        Button {
            Task {
                if let target = await store.makeResumeTarget(for: session.ref) {
                    TerminalLauncher.launch(target: target, in: store.selectedTerminal)
                }
            }
        } label: {
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("resumeButton_\(session.ref.sessionID)")
        .help("Resume session")
    }

    private var sessionIdView: some View {
        Text(String(session.ref.sessionID.prefix(8)))
            .onTapGesture {
                TerminalLauncher.copyToClipboard(session.ref.sessionID)
            }
            .help("Click to copy full session ID")
    }

    private func metaItem(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 2) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
        }
    }

    private var metaSeparator: some View {
        Text("\u{00B7}")
            .foregroundStyle(.quaternary)
    }

    private func signalText(_ signal: HealthSignal) -> String {
        switch signal {
        case .stale(let days):
            return "Stale \(days)d"
        case .contextNearFull(let pct, _, _):
            return "Context \(Int(pct * 100))%"
        case .recentErrors(let count):
            return "\(count) error\(count == 1 ? "" : "s")"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
