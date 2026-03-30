import SwiftUI

public struct SettingsView: View {
    @Environment(SessionStore.self) var store

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
            }

            // Scan interval
            Stepper("扫描间隔: \(store.settings.scanIntervalSeconds)s",
                    value: scanIntervalBinding,
                    in: 30...300,
                    step: 10)
            .accessibilityIdentifier("scanIntervalStepper")

            // Save button
            Button("保存设置") {
                store.settings.save()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("saveSettingsButton")
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settingsForm")
        .frame(width: 400, height: 250)
        .padding()
    }

    // Bindings that write through to settings
    private var terminalBinding: Binding<String> {
        Binding(
            get: { store.settings.selectedTerminal },
            set: { store.settings.selectedTerminal = $0 }
        )
    }

    private var dataDirectoryBinding: Binding<String> {
        Binding(
            get: { store.settings.claudeDataDirectory },
            set: { store.settings.claudeDataDirectory = $0 }
        )
    }

    private var scanIntervalBinding: Binding<Int> {
        Binding(
            get: { store.settings.scanIntervalSeconds },
            set: { store.settings.scanIntervalSeconds = $0 }
        )
    }
}
