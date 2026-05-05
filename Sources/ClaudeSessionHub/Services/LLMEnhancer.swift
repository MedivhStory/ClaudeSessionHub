import Foundation

// MARK: - GeneratedUnderstandingField

/// Narrow LLM result for a single field. Used by per-field regenerate
/// flows so the call site doesn't need to invent placeholder values
/// for the other two fields of a full snapshot. `value` is non-optional;
/// when the LLM returns empty / fails, `enhanceField` returns nil at the
/// API layer rather than packaging an empty value.
public struct GeneratedUnderstandingField: Sendable, Equatable {
    public let field: UnderstandingField
    public let value: String
    public let modelName: String
    public let generatedAt: Date
    public let basedOnLastActiveAt: Date

    public init(
        field: UnderstandingField,
        value: String,
        modelName: String,
        generatedAt: Date,
        basedOnLastActiveAt: Date
    ) {
        self.field = field
        self.value = value
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.basedOnLastActiveAt = basedOnLastActiveAt
    }
}

// MARK: - LLMEnhancer

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

    /// Generate a single field via one LLM call. Returns nil when the
    /// LLM is unconfigured, the call throws, or the cleaned response
    /// is empty. Per-field cleaning matches the full-`enhance` path:
    /// title strips surrounding quotes and truncates to 50 chars;
    /// progress and summary are trimmed-only.
    public func enhanceField(
        _ field: UnderstandingField,
        signals: SessionSignals,
        rawTurns: [String] = [],
        basedOnLastActiveAt: Date
    ) async -> GeneratedUnderstandingField? {
        guard config.isConfigured else { return nil }

        let client = LLMClient(config: config)
        let input = LLMPrompts.titleInput(from: signals, rawTurns: rawTurns)

        let systemPrompt: String
        let maxTokens: Int
        switch field {
        case .title:
            systemPrompt = LLMPrompts.titleSystemPrompt
            maxTokens = 60
        case .progress:
            systemPrompt = LLMPrompts.progressSystemPrompt
            maxTokens = 100
        case .summary:
            systemPrompt = LLMPrompts.summarySystemPrompt
            maxTokens = 200
        }

        let response: String
        do {
            response = try await client.complete(
                systemPrompt: systemPrompt,
                userMessage: input,
                maxTokens: maxTokens
            )
        } catch {
            return nil
        }

        let cleaned: String
        switch field {
        case .title:
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !trimmed.isEmpty else { return nil }
            cleaned = String(trimmed.prefix(50))
        case .progress, .summary:
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            cleaned = trimmed
        }

        return GeneratedUnderstandingField(
            field: field,
            value: cleaned,
            modelName: config.modelName,
            generatedAt: Date(),
            basedOnLastActiveAt: basedOnLastActiveAt
        )
    }
}
