import SwiftUI

public struct ContentView: View {
    @Environment(SessionStore.self) var store
    @State private var showOverview = false
    @State private var selectedProject: String?
    @State private var statusFilter: RuntimeState?
    @State private var agentFilter: ProviderID?
    @State private var searchText = ""

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
                Text("Overview \u{2014} coming in Task 9")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SessionListView(
                    searchText: $searchText,
                    selectedProject: selectedProject,
                    statusFilter: statusFilter,
                    agentFilter: agentFilter
                )
            }
        }
        .task {
            await store.performScan()
        }
    }
}
