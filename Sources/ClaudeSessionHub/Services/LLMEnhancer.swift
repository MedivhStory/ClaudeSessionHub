import Foundation

/// Produces a complete LLMUnderstandingSnapshot from SessionSignals.
/// Returns nil when LLM is unconfigured or all calls fail.
/// This is an independent service — NOT a SessionTitleStrategy conformance.
public struct LLMEnhancer: Sendable {
    private let config: LLMConfig

    public init(config: LLMConfig) {
        self.config = config
    }

    /// Generate a complete AI understanding snapshot for a session.
    /// Returns nil if LLM is unconfigured or title generation fails.
    public func enhance(signals: SessionSignals, rawTurns: [String] = [], basedOnLastActiveAt: Date) async -> LLMUnderstandingSnapshot? {
        guard config.isConfigured else { return nil }

        let client = LLMClient(config: config)
        let input = LLMPrompts.titleInput(from: signals, rawTurns: rawTurns)

        // Title is required — if this fails, return nil
        let title: String
        do {
            let response = try await client.complete(
                systemPrompt: LLMPrompts.titleSystemPrompt,
                userMessage: input,
                maxTokens: 60
            )
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !cleaned.isEmpty else { return nil }
            title = String(cleaned.prefix(50))
        } catch {
            return nil
        }

        // Progress — optional, failure is ok
        var progress: String? = nil
        do {
            let response = try await client.complete(
                systemPrompt: LLMPrompts.progressSystemPrompt,
                userMessage: input,
                maxTokens: 100
            )
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { progress = cleaned }
        } catch {}

        // Summary — optional, failure is ok
        var summary: String? = nil
        do {
            let response = try await client.complete(
                systemPrompt: LLMPrompts.summarySystemPrompt,
                userMessage: input,
                maxTokens: 200
            )
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { summary = cleaned }
        } catch {}

        return LLMUnderstandingSnapshot(
            sessionID: signals.sessionID,
            title: title,
            progress: progress,
            summary: summary,
            modelName: config.modelName,
            generatedAt: Date(),
            basedOnLastActiveAt: basedOnLastActiveAt
        )
    }
}
