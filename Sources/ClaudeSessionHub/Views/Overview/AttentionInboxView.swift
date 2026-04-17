import SwiftUI

struct AttentionInboxView: View {
    @Environment(SessionStore.self) var store
    let attentionSessions: [SessionSummary]
    let activeSessions: [SessionSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Attention Inbox
            sectionHeader(
                icon: "exclamationmark.triangle.fill",
                title: "Attention Inbox",
                color: .orange,
                count: attentionSessions.count
            )

            if attentionSessions.isEmpty {
                Text("No sessions need attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            } else {
                ForEach(attentionSessions, id: \.ref) { session in
                    attentionRow(session)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Active Sessions (dedup: exclude attention sessions)
            sectionHeader(
                icon: "bolt.fill",
                title: "Active Sessions",
                color: .green,
                count: activeSessions.count
            )

            if activeSessions.isEmpty {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            } else {
                ForEach(activeSessions, id: \.ref) { session in
                    activeRow(session)
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attentionInbox")
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
    }

    // MARK: - Attention Row (compact)

    private func attentionRow(_ session: SessionSummary) -> some View {
        let signals = HealthEngine.computeSignals(for: session)
        let borderColor = borderColorFor(signals)

        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(borderColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let cwd = session.cwd {
                        Text(ProjectNameResolver.displayName(for: cwd))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(signals.map(signalText).joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text(relativeTime(session.lastActiveAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            if session.runtimeState == .stopped {
                resumeButton(for: session)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Active Row (compact)

    private func activeRow(_ session: SessionSummary) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.green)
                .frame(width: 3)

            Text(session.title)
                .font(.callout)
                .lineLimit(1)

            if let cwd = session.cwd {
                Text(ProjectNameResolver.displayName(for: cwd))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(relativeTime(session.lastActiveAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func resumeButton(for session: SessionSummary) -> some View {
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
        .help("Resume session")
    }

    private func borderColorFor(_ signals: [HealthSignal]) -> Color {
        for signal in signals {
            switch signal {
            case .stale:
                return .orange
            case .contextNearFull, .recentErrors:
                return .red
            }
        }
        return .orange
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
