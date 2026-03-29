import Foundation

public final class CodexProvider: AgentProvider, @unchecked Sendable {
    public let id: ProviderID = "codex"
    public let displayName = "Codex"
    public let capabilities: ProviderCapabilities = [.resume]

    public init() {}

    public func discoverSessions() async throws -> [SessionSummary] { [] }

    public func loadSessionDetail(for ref: SessionRef) async throws -> SessionDetail {
        throw CocoaError(.featureUnsupported)
    }

    public func makeResumeTarget(for ref: SessionRef) throws -> ResumeTarget {
        ResumeTarget(
            executable: "codex",
            arguments: ["-r", ref.sessionID],
            workingDirectory: nil,
            displayCommand: "codex -r \(ref.sessionID)"
        )
    }

    public func refreshRuntimeState(for refs: [SessionRef]) async -> [SessionRef: SessionRuntimeState] { [:] }
}
