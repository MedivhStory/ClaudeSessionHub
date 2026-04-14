// Sources/EvalHarnessCore/PromptBuilderHasher.swift
import Foundation
import CryptoKit
import ClaudeSessionHubLib

public enum PromptBuilderHasher {
    public static func currentHash() -> String {
        let blob = canonicalBlob()
        let digest = SHA256.hash(data: Data(blob.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    public static func canonicalBlob() -> String {
        return "titleSystemPrompt=" + LLMPrompts.titleSystemPrompt + "\n"
             + "progressSystemPrompt=" + LLMPrompts.progressSystemPrompt + "\n"
             + "summarySystemPrompt=" + LLMPrompts.summarySystemPrompt + "\n"
             + "titleInputSource=" + GeneratedPromptSource.titleInputFunctionSource
    }
}
