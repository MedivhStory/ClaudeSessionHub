import SwiftUI
import ClaudeSessionHubLib

@main
struct ClaudeSessionHubApp: App {
    @State private var store: SessionStore

    init() {
        let settings = SettingsStore()
        let providers: [any AgentProvider] = [
            ClaudeProvider(baseDirectory: settings.claudeDataDirectory),
            CodexProvider()
        ]
        let coordinator = ScanCoordinator(providers: providers)
        _store = State(initialValue: SessionStore(coordinator: coordinator, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
