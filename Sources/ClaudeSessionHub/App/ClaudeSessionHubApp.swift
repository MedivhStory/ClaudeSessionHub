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

        // UI test mode uses a temp directory for all stores so tests are
        // isolated from real user settings (e.g. selectedTerminal).
        let hubDirectory: String
        if isUITestMode {
            let tempDir = NSTemporaryDirectory() + "claude-hub-uitest-\(ProcessInfo.processInfo.processIdentifier)"
            try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
            hubDirectory = tempDir
        } else {
            hubDirectory = NSHomeDirectory() + "/.claude-hub"
        }

        let settings = SettingsStore(directory: hubDirectory,
                                     secretStore: isUITestMode ? InMemorySecretStore() : FileSecretStore(directory: hubDirectory))

        let providers: [any AgentProvider]
        if isUITestMode {
            providers = [FixtureProvider()]
        } else {
            // Dynamic provider: reads settings.claudeDataDirectory on each scan,
            // so changing the data directory takes effect without restart.
            providers = [
                ClaudeProvider(baseDirectoryProvider: { [settings] in settings.claudeDataDirectory }),
                CodexProvider()
            ]
        }
        let coordinator = ScanCoordinator(providers: providers)
        let labelStore = LabelStore(directory: hubDirectory)
        let archiveStore = ArchiveStore(directory: hubDirectory)
        let titleStore = TitleStore(directory: hubDirectory)
        let understandingStore = UnderstandingStore(directory: hubDirectory)
        let understandingV2 = UnderstandingStoreV2(directory: hubDirectory)
        let legacyAdapter = LegacyUnderstandingAdapter(directory: hubDirectory)
        let displayPolicy = UnderstandingDisplayPolicy()
        let signalExtractor: SignalExtractor
        if isUITestMode {
            signalExtractor = SignalExtractor()
        } else {
            signalExtractor = SignalExtractor(baseDirectoryProvider: { [settings] in settings.claudeDataDirectory })
        }
        _store = State(initialValue: SessionStore(
            coordinator: coordinator,
            labelStore: labelStore,
            archiveStore: archiveStore,
            settings: settings,
            titleStore: titleStore,
            signalExtractor: signalExtractor,
            understandingStore: understandingStore,
            understandingV2: understandingV2,
            legacyAdapter: legacyAdapter,
            displayPolicy: displayPolicy
        ))
    }

    var body: some Scene {
        WindowGroup("Claude Session Hub") {
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
            }
            CommandMenu("AI") {
                BatchEnhanceMenuItem()
                    .environment(store)
            }
        }
        Settings {
            SettingsView()
                .environment(store)
        }
        Window("关于 Claude Session Hub", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

/// Helper view that holds @Environment(\.openWindow) for the menu item.
private struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("关于 Claude Session Hub") {
            openWindow(id: "about")
        }
    }
}

/// Menu-bar command for batch AI enhance on all visible (non-archived) sessions.
private struct BatchEnhanceMenuItem: View {
    @Environment(SessionStore.self) var store

    var body: some View {
        Button("批量 AI 增强全部会话") {
            Task {
                let refs = store.visibleSessions.map(\.ref)
                let _ = await store.batchEnhanceLLM(sessions: refs)
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(!store.settings.llmConfig.isConfigured || store.batchProgress != nil)
    }
}
