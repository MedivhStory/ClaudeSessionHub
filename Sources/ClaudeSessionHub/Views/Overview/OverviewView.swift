import SwiftUI

struct OverviewView: View {
    @Environment(SessionStore.self) var store
    var onNavigateToProject: ((String) -> Void)?
    var onNavigateToSessions: (() -> Void)?

    @State private var filter: OverviewFilter = .all

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Summary cards
                SummaryCardsView(
                    attentionCount: store.attentionSessions.count,
                    activeCount: store.activeSessions.count,
                    projectCount: store.projects.count,
                    lastScanTime: store.lastScanTime
                )

                // Heat strip
                HeatStripView(
                    projects: store.projects,
                    onSelectProject: onNavigateToProject
                )
                .padding(.vertical, 4)

                // Filter chips
                FilterChips(
                    selected: $filter,
                    availableAgents: Array(store.activeProviderIDs)
                )

                Divider()
                    .padding(.vertical, 4)

                // Main content: responsive layout
                GeometryReader { geo in
                    if geo.size.width > 600 {
                        dualColumn
                    } else {
                        singleColumn
                    }
                }
                .frame(minHeight: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("overviewRoot")
    }

    // MARK: - Filtered Data

    private var filteredAttentionSessions: [SessionSummary] {
        store.attentionSessions.filter(matchesFilter)
    }

    /// Active sessions excluding those already in attention inbox
    private var filteredActiveSessions: [SessionSummary] {
        let attentionRefs = Set(filteredAttentionSessions.map(\.ref))
        return store.activeSessions
            .filter { !attentionRefs.contains($0.ref) }
            .filter(matchesFilter)
    }

    private var filteredProjects: [String: [SessionSummary]] {
        var result: [String: [SessionSummary]] = [:]
        for (name, sessions) in store.projects {
            let filtered = sessions.filter(matchesFilter)
            if !filtered.isEmpty {
                result[name] = filtered
            }
        }
        return result
    }

    private var recentlyFinished: [SessionSummary] {
        store.visibleSessions
            .filter { $0.taskPhase == .done }
            .filter(matchesFilter)
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .prefix(3)
            .map { $0 }
    }

    private func matchesFilter(_ session: SessionSummary) -> Bool {
        switch filter {
        case .all:
            return true
        case .attention:
            return !HealthEngine.computeSignals(for: session).isEmpty
        case .active:
            return session.runtimeState == .active
        case .agent(let id):
            return session.ref.providerID == id
        case .recent7d:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return session.lastActiveAt >= sevenDaysAgo
        }
    }

    // MARK: - Layouts

    private var dualColumn: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: Attention + Active
            AttentionInboxView(
                attentionSessions: filteredAttentionSessions,
                activeSessions: filteredActiveSessions
            )
            .frame(maxWidth: .infinity)

            Divider()

            // Right column: Portfolio
            ProjectPortfolioView(
                projects: filteredProjects,
                recentlyFinished: recentlyFinished,
                onSelectProject: onNavigateToProject,
                onNavigateToSessions: onNavigateToSessions
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var singleColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            AttentionInboxView(
                attentionSessions: filteredAttentionSessions,
                activeSessions: filteredActiveSessions
            )

            Divider()

            ProjectPortfolioView(
                projects: filteredProjects,
                recentlyFinished: recentlyFinished,
                onSelectProject: onNavigateToProject,
                onNavigateToSessions: onNavigateToSessions
            )
        }
    }
}
