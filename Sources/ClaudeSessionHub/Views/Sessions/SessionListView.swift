import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) var store
    @Binding var searchText: String
    var selectedProject: String?
    var statusFilter: RuntimeState?
    var agentFilter: ProviderID?
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal)
                .padding(.top, 8)

            // Search bar
            SearchBar(text: $searchText, isFocused: searchFocused)
                .padding(.horizontal)
                .padding(.vertical, 6)

            // Session list
            if filteredSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSessions) { session in
                            SessionTileView(session: session, searchQuery: searchText)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .animation(nil, value: filteredSessions.map(\.ref))
                }
                .accessibilityIdentifier("sessionList")
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
                    .accessibilityIdentifier("sessionListProjectTitle")
                Text("-- \(filteredSessions.count) sessions")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sessionCount")
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

            if let progress = store.batchProgress {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("\(progress.current)/\(progress.total) 增强中...")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                }
            } else if store.settings.llmConfig.isConfigured {
                Button {
                    Task {
                        let refs = filteredSessions.map(\.ref)
                        let _ = await store.batchEnhanceLLM(sessions: refs)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("批量 AI 增强")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("batchEnhanceButton")
            }
        }
    }

    // MARK: - Empty State

    private var dataDirExists: Bool {
        FileManager.default.fileExists(atPath: store.settings.claudeDataDirectory)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if !searchText.isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No sessions match \"\(searchText)\"")
                    .foregroundStyle(.secondary)
            } else if store.visibleSessions.isEmpty && !dataDirExists {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("未找到 Claude Code 数据目录，请在设置中配置路径")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("missingDataDirNotice")
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
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
        var result = store.visibleSessions

        // Filter by project
        if let project = selectedProject {
            let projectSessions = store.projects[project] ?? []
            let projectRefs = Set(projectSessions.map(\.ref))
            result = result.filter { projectRefs.contains($0.ref) }
        }

        // Filter by agent
        if let agent = agentFilter {
            result = result.filter { $0.ref.providerID == agent }
        }

        // Filter by status
        if let state = statusFilter {
            result = result.filter { $0.runtimeState == state }
        }

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter { SearchBar.matches($0, query: searchText, store: store) }
        }

        return result
    }
}
