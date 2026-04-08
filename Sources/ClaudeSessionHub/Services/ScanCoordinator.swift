import Foundation

public actor ScanCoordinator {
    private let providers: [any AgentProvider]
    public private(set) var lastScanTime: Date?

    public init(providers: [any AgentProvider]) {
        self.providers = providers
    }

    public func scan() async -> [SessionSummary] {
        var allSessions: [SessionSummary] = []

        await withTaskGroup(of: [SessionSummary].self) { group in
            for provider in providers {
                group.addTask {
                    (try? await provider.discoverSessions()) ?? []
                }
            }
            for await sessions in group {
                allSessions.append(contentsOf: sessions)
            }
        }

        // Dedup by SessionRef (providerID + sessionID), keep first occurrence
        var seen = Set<SessionRef>()
        let deduped = allSessions.filter { seen.insert($0.ref).inserted }

        lastScanTime = Date()
        return deduped
    }

    public func refreshRuntime(sessions: [SessionSummary]) async -> [SessionRef: SessionRuntimeState] {
        var results: [SessionRef: SessionRuntimeState] = [:]
        let byProvider = Dictionary(grouping: sessions.map(\.ref)) { $0.providerID }
        await withTaskGroup(of: [SessionRef: SessionRuntimeState].self) { group in
            for provider in providers {
                if let refs = byProvider[provider.id] {
                    group.addTask {
                        await provider.refreshRuntimeState(for: refs)
                    }
                }
            }
            for await partial in group {
                results.merge(partial) { _, new in new }
            }
        }
        return results
    }

    public func provider(for providerID: ProviderID) -> (any AgentProvider)? {
        providers.first(where: { $0.id == providerID })
    }

    public var activeProviders: [any AgentProvider] {
        providers
    }
}
