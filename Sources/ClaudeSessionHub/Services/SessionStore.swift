import Foundation
import Observation

@Observable
public final class SessionStore: @unchecked Sendable {
    @MainActor public private(set) var sessions: [SessionSummary] = []
    @MainActor public private(set) var lastScanTime: Date?
    @MainActor public private(set) var isScanning = false

    private let coordinator: ScanCoordinator
    public let labelStore: LabelStore
    public let settings: SettingsStore

    public init(coordinator: ScanCoordinator, labelStore: LabelStore = LabelStore(), settings: SettingsStore = SettingsStore()) {
        self.coordinator = coordinator
        self.labelStore = labelStore
        self.settings = settings
    }

    @MainActor
    public func performScan() async {
        isScanning = true
        defer { isScanning = false }

        let results = await coordinator.scan()
        sessions = results.sorted { $0.lastActiveAt > $1.lastActiveAt }
        lastScanTime = await coordinator.lastScanTime
    }

    // MARK: - Derived computed properties

    @MainActor
    public var projects: [String: [SessionSummary]] {
        // Resolve collisions first: two cwds with same basename get disambiguated
        let allCwds = Array(Set(sessions.compactMap(\.cwd)))
        let nameMap = ProjectNameResolver.resolveCollisions(allCwds)

        return Dictionary(grouping: sessions) { session in
            guard let cwd = session.cwd else { return "Unknown" }
            return nameMap[cwd] ?? ProjectNameResolver.displayName(for: cwd)
        }
    }

    @MainActor
    public var activeSessions: [SessionSummary] {
        sessions.filter { $0.runtimeState == .active }
    }

    @MainActor
    public var attentionSessions: [SessionSummary] {
        sessions.filter { !HealthEngine.computeSignals(for: $0).isEmpty }
    }

    @MainActor
    public var activeProviderIDs: Set<ProviderID> {
        Set(sessions.map(\.ref.providerID))
    }

    // MARK: - Provider-delegated actions

    /// Load full session detail via the appropriate provider
    public func loadDetail(for ref: SessionRef) async -> SessionDetail? {
        let providers = await coordinator.activeProviders
        guard let provider = providers.first(where: { $0.id == ref.providerID }) else { return nil }
        return try? await provider.loadSessionDetail(for: ref)
    }

    /// Get a ResumeTarget by delegating to the actual provider.
    /// This ensures provider-specific resume logic (arguments, executable, cwd) is respected.
    public func makeResumeTarget(for ref: SessionRef) async -> ResumeTarget? {
        let providers = await coordinator.activeProviders
        guard let provider = providers.first(where: { $0.id == ref.providerID }) else { return nil }
        return try? provider.makeResumeTarget(for: ref)
    }

    /// Get the user's selected terminal from settings
    @MainActor
    public var selectedTerminal: TerminalLauncher.Terminal {
        TerminalLauncher.Terminal(rawValue: settings.selectedTerminal) ?? .ghostty
    }
}

public enum ProjectNameResolver {
    public static func displayName(for cwd: String) -> String {
        (cwd as NSString).lastPathComponent
    }

    public static func resolveCollisions(_ cwds: [String]) -> [String: String] {
        let basenames = cwds.map { ($0, (($0 as NSString).lastPathComponent)) }
        let counts = Dictionary(grouping: basenames) { $0.1 }.mapValues { $0.count }
        var result: [String: String] = [:]
        for (cwd, base) in basenames {
            if counts[base, default: 0] > 1 {
                let parent = ((cwd as NSString).deletingLastPathComponent as NSString).lastPathComponent
                result[cwd] = "\(base) (\(parent))"
            } else {
                result[cwd] = base
            }
        }
        return result
    }
}
