import Foundation

public protocol AgentProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    func discoverSessions() async throws -> [SessionSummary]
    func loadSessionDetail(for ref: SessionRef) async throws -> SessionDetail
    func makeResumeTarget(for ref: SessionRef) throws -> ResumeTarget
    func refreshRuntimeState(for refs: [SessionRef]) async -> [SessionRef: SessionRuntimeState]
}
