import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) var store
    @Binding var selectedProject: String?
    @Binding var statusFilter: RuntimeState?
    @Binding var agentFilter: ProviderID?

    @State private var agentsExpanded = true
    @State private var projectsExpanded = true
    @State private var statusExpanded = true

    var body: some View {
        List {
            // MARK: - Agents Section
            Section(isExpanded: $agentsExpanded) {
                ForEach(agentRows, id: \.id) { row in
                    Button {
                        agentFilter = (agentFilter == row.id) ? nil : row.id
                        selectedProject = nil
                        statusFilter = nil
                    } label: {
                        HStack {
                            Circle()
                                .fill(row.color)
                                .frame(width: 8, height: 8)
                            Text(row.name)
                            Spacer()
                            Text("\(row.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("AGENTS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Projects Section
            Section(isExpanded: $projectsExpanded) {
                ForEach(projectRows, id: \.name) { row in
                    Button {
                        if selectedProject == row.name {
                            selectedProject = nil
                        } else {
                            selectedProject = row.name
                            statusFilter = nil
                        }
                    } label: {
                        HStack {
                            if row.hasActive {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            }
                            Text(row.name)
                                .fontWeight(selectedProject == row.name ? .semibold : .regular)
                            Spacer()
                            Text("\(row.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedProject == row.name
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            } header: {
                Text("PROJECTS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("projectsSection")

            // MARK: - Status Section
            Section(isExpanded: $statusExpanded) {
                ForEach(RuntimeState.allCases, id: \.self) { state in
                    Button {
                        if statusFilter == state {
                            statusFilter = nil
                        } else {
                            statusFilter = state
                            selectedProject = nil
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(state == .active ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(state == .active ? "Active" : "Stopped")
                                .fontWeight(statusFilter == state ? .semibold : .regular)
                            Spacer()
                            Text("\(countForState(state))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        statusFilter == state
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            } header: {
                Text("STATUS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Data Helpers

    private struct AgentRow: Identifiable {
        let id: ProviderID
        let name: String
        let color: Color
        let count: Int
    }

    private struct ProjectRow {
        let name: String
        let count: Int
        let hasActive: Bool
    }

    private var agentRows: [AgentRow] {
        let grouped = Dictionary(grouping: store.sessions) { $0.ref.providerID }
        return grouped.map { id, sessions in
            let color: Color = id == "claude"
                ? Color(red: 0.48, green: 0.41, blue: 0.93)
                : .teal
            return AgentRow(id: id, name: id == "claude" ? "Claude" : id.capitalized, color: color, count: sessions.count)
        }
        .sorted { $0.count > $1.count }
    }

    private var projectRows: [ProjectRow] {
        store.projects.map { name, sessions in
            ProjectRow(
                name: name,
                count: sessions.count,
                hasActive: sessions.contains { $0.runtimeState == .active }
            )
        }
        .sorted { $0.count > $1.count }
    }

    private func countForState(_ state: RuntimeState) -> Int {
        store.sessions.filter { $0.runtimeState == state }.count
    }
}
