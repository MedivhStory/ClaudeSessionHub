import SwiftUI

struct LLMSettingsSection: View {
    @Environment(SessionStore.self) var store
    @State private var provider: LLMProvider = .custom
    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    @State private var testResult: String?
    @State private var isTesting = false

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

            // API Key
            if provider.requiresApiKey {
                SecureField("API Key", text: $apiKey)
                    .accessibilityIdentifier("llmApiKeyField")
            }

            // Model picker / text field
            if !provider.suggestedModels.isEmpty {
                Picker("模型", selection: $modelName) {
                    ForEach(provider.suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    if !modelName.isEmpty && !provider.suggestedModels.contains(modelName) {
                        Text(modelName).tag(modelName)
                    }
                }
                .accessibilityIdentifier("llmModelPicker")

                TextField("或输入自定义模型名", text: $modelName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("llmModelField")
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
            }
        }
    }

    private func loadConfig() {
        let config = store.settings.llmConfig
        provider = config.provider
        endpoint = config.endpoint
        apiKey = config.apiKey
        modelName = config.modelName
    }

    private func saveConfig() {
        var config = LLMConfig()
        config.provider = provider
        config.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        config.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.setLLMConfig(config)
        testResult = "已保存"
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            var config = LLMConfig()
            config.provider = provider
            config.endpoint = endpoint
            config.apiKey = apiKey
            config.modelName = modelName
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
