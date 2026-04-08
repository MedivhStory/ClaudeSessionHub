import SwiftUI

struct LLMSettingsSection: View {
    @Environment(SessionStore.self) var store
    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Section("AI 增强（可选）") {
            TextField("API 地址", text: $endpoint)
                .help("OpenAI-compatible endpoint")
                .accessibilityIdentifier("llmEndpointField")

            SecureField("API Key", text: $apiKey)
                .accessibilityIdentifier("llmApiKeyField")

            TextField("模型名称", text: $modelName)
                .help("如 gpt-4o, claude-sonnet-4-20250514")
                .accessibilityIdentifier("llmModelField")

            HStack {
                Button("测试连接") {
                    testConnection()
                }
                .disabled(endpoint.isEmpty || apiKey.isEmpty || modelName.isEmpty || isTesting)
                .accessibilityIdentifier("llmTestButton")

                if isTesting {
                    ProgressView().controlSize(.small)
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("成功") ? .green : .red)
                }
            }

            Button("保存 AI 配置") {
                saveConfig()
            }
            .accessibilityIdentifier("llmSaveButton")

            if !store.settings.llmConfig.isConfigured {
                Text("未配置 AI — 使用规则引擎生成标题和进展")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        let config = store.settings.llmConfig
        endpoint = config.endpoint
        apiKey = config.apiKey
        modelName = config.modelName
    }

    private func saveConfig() {
        var config = LLMConfig()
        config.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        config.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.setLLMConfig(config)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            var config = LLMConfig()
            config.endpoint = endpoint
            config.apiKey = apiKey
            config.modelName = modelName
            let client = LLMClient(config: config)
            do {
                let response = try await client.testConnection()
                testResult = "连接成功: \(response)"
            } catch {
                testResult = "失败: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
