import SwiftUI
import AppKit
#if canImport(ClaudeSessionHubLib)
import ClaudeSessionHubLib
#endif

@main
struct ClaudeSessionHubApp: App {
    @State private var store: SessionStore

    init() {
        // Ensure the app runs as a regular macOS app with dock icon and menu bar,
        // even when launched as a bare executable (swift run or Xcode Run on SwiftPM target).
        NSApp.setActivationPolicy(.regular)

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
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first?.makeKeyAndOrderFront(nil)
                    }
                }
        }
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
