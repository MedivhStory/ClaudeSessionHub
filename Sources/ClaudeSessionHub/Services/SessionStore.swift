import Foundation
import Observation

@Observable
public final class SessionStore: @unchecked Sendable {
    @MainActor public private(set) var sessions: [SessionSummary] = []
    @MainActor public private(set) var lastScanTime: Date?
    @MainActor public private(set) var isScanning = false

    private let coordinator: ScanCoordinator
    public let labelStore: LabelStore
    public let archiveStore: ArchiveStore
    public let settings: SettingsStore

    @MainActor public var showArchived = false

    public init(coordinator: ScanCoordinator, labelStore: LabelStore = LabelStore(), archiveStore: ArchiveStore = ArchiveStore(), settings: SettingsStore = SettingsStore()) {
        self.coordinator = coordinator
        self.labelStore = labelStore
        self.archiveStore = archiveStore
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

    @MainActor
    public var visibleSessions: [SessionSummary] {
        sessions.filter { !archiveStore.isArchived($0.ref) || showArchived }
    }

    // MARK: - Derived computed properties
    // All aggregates use visibleSessions (respects archive filter),
    // so sidebar counts, Overview cards, heat strip, and project portfolio
    // are consistent with the session list.

    @MainActor
    public var projects: [String: [SessionSummary]] {
        let visible = visibleSessions
        let allCwds = Array(Set(visible.compactMap(\.cwd)))
        let nameMap = ProjectNameResolver.resolveCollisions(allCwds)

        return Dictionary(grouping: visible) { session in
            guard let cwd = session.cwd else { return "Unknown" }
            return nameMap[cwd] ?? ProjectNameResolver.displayName(for: cwd)
        }
    }

    @MainActor
    public var activeSessions: [SessionSummary] {
        visibleSessions.filter { $0.runtimeState == .active }
    }

    @MainActor
    public var attentionSessions: [SessionSummary] {
        visibleSessions.filter { !HealthEngine.computeSignals(for: $0).isEmpty }
    }

    @MainActor
    public var activeProviderIDs: Set<ProviderID> {
        Set(visibleSessions.map(\.ref.providerID))
    }

    // MARK: - Lightweight PID refresh (cheap, 10s cadence)

    /// Refresh only runtime state (PID liveness) without re-reading JSONL files.
    /// This is the cheap path — does NOT update lastScanTime.
    @MainActor
    public func refreshRuntimeState() async {
        let runtimeStates = await coordinator.refreshRuntime(sessions: sessions)
        // Update runtimeState in place for sessions that changed
        sessions = sessions.map { session in
            guard let state = runtimeStates[session.ref] else { return session }
            let newRuntime: RuntimeState
            switch state {
            case .alive: newRuntime = .active
            case .dead: newRuntime = .stopped
            }
            guard newRuntime != session.runtimeState else { return session }
            return SessionSummary(
                ref: session.ref, title: session.title,
                currentTaskSummary: session.currentTaskSummary,
                runtimeState: newRuntime, taskPhase: session.taskPhase,
                cwd: session.cwd, branch: session.branch,
                turnCount: session.turnCount, filesTouched: session.filesTouched,
                recentErrorCount: session.recentErrorCount,
                createdAt: session.createdAt, lastActiveAt: session.lastActiveAt,
                contextUsage: session.contextUsage
            )
        }
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
