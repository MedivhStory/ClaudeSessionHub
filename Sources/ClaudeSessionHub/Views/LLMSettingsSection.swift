import SwiftUI

struct LLMSettingsSection: View {
    @Environment(SessionStore.self) var store
    @State private var provider: LLMProvider = .custom
    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    @State private var isCustomModel: Bool = false
    @State private var testResult: String?
    @State private var isTesting = false

    private static let customModelTag = "其他..."

    var body: some View {
        Section("AI 增强（可选）") {
            // Provider picker
            Picker("服务商", selection: $provider) {
                ForEach(LLMProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .accessibilityIdentifier("llmProviderPicker")
            .onChange(of: provider) { _, newProvider in
                applyPreset(newProvider)
            }

            // Endpoint (auto-filled for presets, editable for custom)
            if provider == .custom {
                TextField("API 地址", text: $endpoint)
                    .help("OpenAI 兼容的 chat completions 地址")
                    .accessibilityIdentifier("llmEndpointField")
            } else {
                HStack {
                    Text("API 地址")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(endpoint)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // API Key — plain TextField to avoid macOS Passwords autofill trigger.
            // SecureField causes system "Passwords Is Locked" dialog on unsigned apps.
            if provider.requiresApiKey {
                TextField(apiKey.isEmpty
                          ? "API Key（已安全存储，留空则不修改）"
                          : "API Key",
                          text: $apiKey)
                    .textContentType(.none)
                    .accessibilityIdentifier("llmApiKeyField")
            }

            // Model picker / text field
            if !provider.suggestedModels.isEmpty {
                Picker("模型", selection: Binding(
                    get: { isCustomModel ? Self.customModelTag : modelName },
                    set: { picked in
                        if picked == Self.customModelTag {
                            isCustomModel = true
                            modelName = ""
                        } else {
                            isCustomModel = false
                            modelName = picked
                        }
                    }
                )) {
                    ForEach(provider.suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    Text(Self.customModelTag).tag(Self.customModelTag)
                }
                .accessibilityIdentifier("llmModelPicker")

                if isCustomModel {
                    TextField("模型名称", text: $modelName)
                        .help("如 gpt-4o, qwen-plus")
                        .accessibilityIdentifier("llmModelField")
                }
            } else {
                TextField("模型名称", text: $modelName)
                    .help("如 gpt-4o, qwen-plus")
                    .accessibilityIdentifier("llmModelField")
            }

            // Test + Save
            HStack {
                Button("测试连接") {
                    testConnection()
                }
                .disabled(!canTest || isTesting)
                .accessibilityIdentifier("llmTestButton")

                Button("保存配置") {
                    saveConfig()
                }
                .accessibilityIdentifier("llmSaveButton")

                if isTesting {
                    ProgressView().controlSize(.small)
                }

                if let result = testResult {
                    Text(result)
                        .font(.system(size: 11))
                        .foregroundStyle(result.contains("成功") ? .green : .red)
                        .lineLimit(2)
                }
            }

            // Status
            if store.settings.llmConfig.isConfigured {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                    Text("已配置: \(store.settings.llmConfig.provider.displayName) / \(store.settings.llmConfig.modelName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("未配置 AI — 使用规则引擎生成标题和进展")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadConfig() }
    }

    private var canTest: Bool {
        !endpoint.isEmpty && !modelName.isEmpty &&
        (!provider.requiresApiKey || !apiKey.isEmpty)
    }

    private func applyPreset(_ p: LLMProvider) {
        if p != .custom {
            endpoint = p.defaultBaseURL
            if let first = p.suggestedModels.first {
                modelName = first
                isCustomModel = false
            }
        }
    }

    private func loadConfig() {
        // Do NOT read Keychain here — only load non-secret fields from config.
        // apiKey stays empty in the UI. User re-enters or it's loaded on save/test.
        let config = store.settings.llmConfig
        provider = config.provider
        endpoint = config.endpoint
        apiKey = ""  // Don't read from Keychain just to display
        modelName = config.modelName
        isCustomModel = !config.modelName.isEmpty && !config.provider.suggestedModels.contains(config.modelName)
    }

    private func buildCurrentConfig() -> LLMConfig {
        var config = LLMConfig()
        config.provider = provider
        config.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        config.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return config
    }

    private func saveConfig() {
        var config = buildCurrentConfig()
        // If user left apiKey empty and we already have one in Keychain, keep it
        if config.apiKey.isEmpty {
            store.settings.ensureApiKeyLoaded()
            config.apiKey = store.settings.llmConfig.apiKey
        }
        store.settings.setLLMConfig(config)
        testResult = "已保存"
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let config = buildCurrentConfig()
        Task {
            let client = LLMClient(config: config)
            do {
                let response = try await client.testConnection()
                testResult = "连接成功: \(String(response.prefix(50)))"
            } catch {
                testResult = "失败: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
