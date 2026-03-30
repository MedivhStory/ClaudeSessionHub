import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) var store
    @Binding var searchText: String
    var selectedProject: String?
    var statusFilter: RuntimeState?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal)
                .padding(.top, 8)

            // Search bar
            SearchBar(text: $searchText)
                .padding(.horizontal)
                .padding(.vertical, 6)

            // Session list
            if filteredSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSessions) { session in
                            SessionTileView(session: session)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if let project = selectedProject {
                Text(project)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("-- \(filteredSessions.count) sessions")
                    .foregroundStyle(.secondary)
            } else if let filter = statusFilter {
                Text(filter == .active ? "Active Sessions" : "Stopped Sessions")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("-- \(filteredSessions.count)")
                    .foregroundStyle(.secondary)
            } else {
                Text("All Sessions")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("-- \(filteredSessions.count)")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            if !searchText.isEmpty {
                Text("No sessions match \"\(searchText)\"")
                    .foregroundStyle(.secondary)
            } else {
                Text("No sessions found")
                    .foregroundStyle(.secondary)
                Text("Run `claude` in a terminal to create a session.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filtering

    private var filteredSessions: [SessionSummary] {
        var result = store.sessions

        // Filter by project
        if let project = selectedProject {
            let projectSessions = store.projects[project] ?? []
            let projectRefs = Set(projectSessions.map(\.ref))
            result = result.filter { projectRefs.contains($0.ref) }
        }

        // Filter by status
        if let state = statusFilter {
            result = result.filter { $0.runtimeState == state }
        }

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter { SearchBar.matches($0, query: searchText) }
        }

        return result
    }
}
