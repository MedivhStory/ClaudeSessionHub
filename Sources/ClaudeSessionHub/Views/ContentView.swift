import SwiftUI

public struct ContentView: View {
    @Environment(SessionStore.self) var store
    @State private var showOverview = false
    @State private var selectedProject: String?
    @State private var statusFilter: RuntimeState?
    @State private var agentFilter: ProviderID?
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // View toggle at the top of the sidebar
                Picker("View", selection: $showOverview) {
                    Text("Sessions").tag(false)
                    Text("Overview").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("viewToggle")
                .padding(8)

                SidebarView(
                    selectedProject: $selectedProject,
                    statusFilter: $statusFilter,
                    agentFilter: $agentFilter
                )
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if showOverview {
                OverviewView(
                    onNavigateToProject: { project in
                        // Clear all filters before navigating — prevents stale filters
                        // from hiding sessions in the target project
                        statusFilter = nil
                        agentFilter = nil
                        searchText = ""
                        selectedProject = project
                        showOverview = false
                    },
                    onNavigateToSessions: {
                        // Clear filters for clean "View All" landing
                        statusFilter = nil
                        agentFilter = nil
                        searchText = ""
                        selectedProject = nil
                        showOverview = false
                    }
                )
            } else {
                SessionListView(
                    searchText: $searchText,
                    selectedProject: selectedProject,
                    statusFilter: statusFilter,
                    agentFilter: agentFilter,
                    searchFocused: $searchFieldFocused
                )
            }
        }
        .overlay {
            Button("") {
                searchFieldFocused = true
                showOverview = false
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .withScanTimers()
        .task {
            await store.performScan()
        }
    }
}
