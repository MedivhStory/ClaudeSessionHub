import SwiftUI
import AppKit
#if canImport(ClaudeSessionHubLib)
import ClaudeSessionHubLib
#endif

@main
struct ClaudeSessionHubApp: App {
    @State private var store: SessionStore

    init() {
        // NOTE: Do NOT call NSApp / NSApplication.shared here.
        // In SwiftUI's @main lifecycle, NSApplication may not be initialized yet
        // during App.init(). This causes a nil crash under XCUITest launch paths.
        // All NSApp calls are deferred to .onAppear where NSApplication is guaranteed ready.

        let isUITestMode = CommandLine.arguments.contains("--ui-test-mode")
        let settings = SettingsStore()

        let providers: [any AgentProvider]
        if isUITestMode {
            providers = [FixtureProvider()]
        } else {
            providers = [
                ClaudeProvider(baseDirectory: settings.claudeDataDirectory),
                CodexProvider()
            ]
        }
        let coordinator = ScanCoordinator(providers: providers)
        _store = State(initialValue: SessionStore(coordinator: coordinator, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    // Safe here: NSApplication is fully initialized by the time
                    // the first view appears. Works for all three launch paths:
                    // 1. swift run ClaudeSessionHub (bare executable)
                    // 2. Xcode Run (SwiftPM or xcodeproj)
                    // 3. XCUITest app launch
                    let app = NSApplication.shared
                    app.setActivationPolicy(.regular)
                    DispatchQueue.main.async {
                        app.activate(ignoringOtherApps: true)
                        app.windows.first?.makeKeyAndOrderFront(nil)
                    }
                }
        }
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
