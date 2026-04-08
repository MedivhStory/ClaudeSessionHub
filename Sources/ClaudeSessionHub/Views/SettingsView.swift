import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct SettingsView: View {
    @Environment(SessionStore.self) var store
    @State private var showSavedFeedback = false

    public init() {}

    public var body: some View {
        Form {
            // Terminal selection
            Picker("默认终端", selection: terminalBinding) {
                ForEach(TerminalLauncher.Terminal.allCases, id: \.self) { terminal in
                    Text(terminal.rawValue).tag(terminal.rawValue)
                }
            }
            .accessibilityIdentifier("terminalPicker")

            // Data directory — requires app restart to take effect
            TextField("Claude 数据目录", text: dataDirectoryBinding)
                .accessibilityIdentifier("dataDirectoryField")
                .help("默认: ~/.claude — 修改后需重启应用生效")
            if store.settings.claudeDataDirectory != (NSHomeDirectory() + "/.claude") {
                Text("数据目录已修改，保存后需重启应用生效")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("restartHint")
            }

            // Scan interval
            Stepper("扫描间隔: \(store.settings.scanIntervalSeconds)s",
                    value: scanIntervalBinding,
                    in: 30...300,
                    step: 10)
            .accessibilityIdentifier("scanIntervalStepper")

            // Save button with feedback
            Button(showSavedFeedback ? "已保存 ✓" : "保存设置") {
                store.settings.save()
                showSavedFeedback = true
                // Auto-close Settings window after brief feedback.
                // @Environment(\.dismiss) doesn't work in macOS Settings scene,
                // so we close via NSApp.keyWindow directly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    #if canImport(AppKit)
                    // Find and close the Settings window (not the main window)
                    for window in NSApp.windows where window.isKeyWindow && window != NSApp.windows.first {
                        window.close()
                        break
                    }
                    #endif
                    showSavedFeedback = false
                }
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("saveSettingsButton")
            .disabled(showSavedFeedback)

            LLMSettingsSection()
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settingsForm")
        .frame(width: 400, height: 500)
        .padding()
    }

    // Bindings that write through to settings via auto-save setters
    private var terminalBinding: Binding<String> {
        Binding(
            get: { store.settings.selectedTerminal },
            set: { store.settings.setSelectedTerminal($0) }
        )
    }

    private var dataDirectoryBinding: Binding<String> {
        Binding(
            get: { store.settings.claudeDataDirectory },
            set: { store.settings.setClaudeDataDirectory($0) }
        )
    }

    private var scanIntervalBinding: Binding<Int> {
        Binding(
            get: { store.settings.scanIntervalSeconds },
            set: { store.settings.setScanIntervalSeconds($0) }
        )
    }
}
