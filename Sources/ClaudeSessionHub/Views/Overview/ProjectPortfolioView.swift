import SwiftUI

struct ProjectPortfolioView: View {
    let projects: [String: [SessionSummary]]
    let recentlyFinished: [SessionSummary]
    var onSelectProject: ((String) -> Void)?
    var onNavigateToSessions: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Portfolio")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(sortedProjectNames, id: \.self) { name in
                projectCard(name: name, sessions: projects[name] ?? [])
            }

            if !recentlyFinished.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Recently Finished")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(recentlyFinished, id: \.ref) { session in
                    finishedRow(session)
                }
            }

            if let onNavigateToSessions {
                Button {
                    onNavigateToSessions()
                } label: {
                    HStack(spacing: 4) {
                        Text("View All in Sessions")
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("viewAllSessions")
                .padding(.top, 4)
            }
        }
        .padding(12)
    }

    // MARK: - Sorting

    private var sortedProjectNames: [String] {
        projects.keys.sorted { lhs, rhs in
            let lActive = projects[lhs]?.filter { $0.runtimeState == .active }.count ?? 0
            let rActive = projects[rhs]?.filter { $0.runtimeState == .active }.count ?? 0
            if lActive != rActive { return lActive > rActive }
            let lAttn = projects[lhs]?.filter { !HealthEngine.computeSignals(for: $0).isEmpty }.count ?? 0
            let rAttn = projects[rhs]?.filter { !HealthEngine.computeSignals(for: $0).isEmpty }.count ?? 0
            if lAttn != rAttn { return lAttn > rAttn }
            let lCount = projects[lhs]?.count ?? 0
            let rCount = projects[rhs]?.count ?? 0
            if lCount != rCount { return lCount > rCount }
            return lhs < rhs  // stable tiebreaker
        }
    }

    // MARK: - Project Card

    private func projectCard(name: String, sessions: [SessionSummary]) -> some View {
        let activeCount = sessions.filter { $0.runtimeState == .active }.count
        let attentionCount = sessions.filter { !HealthEngine.computeSignals(for: $0).isEmpty }.count
        let topSession = sessions
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .first

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                if let onSelectProject {
                    Button {
                        onSelectProject(name)
                    } label: {
                        HStack(spacing: 2) {
                            Text("Open")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("openProject_\(name)")
                }
            }

            HStack(spacing: 8) {
                statLabel("\(sessions.count) sessions", color: .secondary)
                if activeCount > 0 {
                    statLabel("\(activeCount) active", color: .green)
                }
                if attentionCount > 0 {
                    statLabel("\(attentionCount) attn", color: .orange)
                }
            }

            if let top = topSession, let summary = top.currentTaskSummary, !summary.isEmpty {
                HStack(spacing: 4) {
                    Text("Top:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Show signals for attention sessions
            let attentionSessions = sessions.filter { !HealthEngine.computeSignals(for: $0).isEmpty }
            if !attentionSessions.isEmpty {
                let allSignals = attentionSessions.flatMap { HealthEngine.computeSignals(for: $0) }
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(allSignals.prefix(2).map(signalText).joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectCard_\(name)")
    }

    // MARK: - Finished Row

    private func finishedRow(_ session: SessionSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.gray)

            Text(session.title)
                .font(.caption)
                .lineLimit(1)

            if let cwd = session.cwd {
                Text(ProjectNameResolver.displayName(for: cwd))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(relativeTime(session.lastActiveAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func statLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
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
