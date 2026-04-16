import Foundation
import Observation

@Observable
public final class SessionStore: @unchecked Sendable {
    @MainActor public private(set) var sessions: [SessionSummary] = []
    @MainActor public private(set) var lastScanTime: Date?
    @MainActor public private(set) var isScanning = false
    @MainActor public private(set) var batchProgress: (current: Int, total: Int)? = nil

    private let coordinator: ScanCoordinator
    public let labelStore: LabelStore
    public let archiveStore: ArchiveStore
    public let settings: SettingsStore
    public let titleStore: TitleStore
    public let understandingStore: UnderstandingStore
    private let signalExtractor: SignalExtractor
    private let titleStrategy: any SessionTitleStrategy
    @MainActor private var historyTextsCache: [String: [String]] = [:]

    @MainActor public var showArchived = false

    public init(coordinator: ScanCoordinator,
                labelStore: LabelStore = LabelStore(),
                archiveStore: ArchiveStore = ArchiveStore(),
                settings: SettingsStore = SettingsStore(),
                titleStore: TitleStore = TitleStore(),
                signalExtractor: SignalExtractor = SignalExtractor(),
                titleStrategy: any SessionTitleStrategy = RuleTitleStrategy(),
                understandingStore: UnderstandingStore = UnderstandingStore()) {
        self.coordinator = coordinator
        self.labelStore = labelStore
        self.archiveStore = archiveStore
        self.settings = settings
        self.titleStore = titleStore
        self.signalExtractor = signalExtractor
        self.titleStrategy = titleStrategy
        self.understandingStore = understandingStore
    }

    @MainActor
    public func performScan() async {
        // Re-entry guard: skip if already scanning (prevents overlapping full scans
        // from .task + didBecomeActive + timer firing simultaneously at startup)
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let results = await coordinator.scan()
        // Stable sort: primary by lastActiveAt desc, secondary by sessionID for deterministic order
        sessions = results.sorted {
            if $0.lastActiveAt != $1.lastActiveAt {
                return $0.lastActiveAt > $1.lastActiveAt
            }
            return $0.ref.sessionID < $1.ref.sessionID
        }
        lastScanTime = await coordinator.lastScanTime
        await generateTitlesForNewSessions(sessions)
    }

    // MARK: - Title Generation

    @MainActor
    private func generateTitlesForNewSessions(_ sessions: [SessionSummary]) async {
        for session in sessions {
            let sid = session.ref.sessionID

            // Always populate history cache for search (even if title already exists)
            let historyTexts = signalExtractor.historyDisplayTexts(for: sid)
            historyTextsCache[sid] = historyTexts

            let currentTitle = titleStore.currentTitle(for: sid)
            let isPlaceholder = currentTitle?.source == .placeholder
            let hasRealTitle = currentTitle != nil && !isPlaceholder

            // Skip if already has a real (non-placeholder) title
            guard !hasRealTitle else { continue }

            // Extract signals — lookup provider via coordinator (actor call)
            guard let provider = await coordinator.provider(for: session.ref.providerID) as? ClaudeProvider,
                  var signals = try? await provider.extractSignals(for: session.ref) else { continue }

            // Enrich with history + tasks
            signals = signalExtractor.enrich(signals)

            // Check gate
            if titleStrategy.shouldGenerateFirstTitle(for: signals) {
                // Full title + progress generation (auto-upgrades placeholder)
                let title = titleStrategy.generateTitle(from: signals)
                titleStore.setTitle(for: sid, title: title)

                let progress = titleStrategy.extractLastProgress(from: signals)
                titleStore.setLastProgress(for: sid, progress: progress)
            } else if currentTitle == nil {
                // Gate failed and no title yet — try descriptive placeholder
                if let placeholder = titleStrategy.generatePlaceholderTitle(from: signals) {
                    titleStore.setTitle(for: sid, title: placeholder)
                }
            }
        }
    }

    @MainActor
    public func refreshTitle(for ref: SessionRef) async {
        guard let provider = await coordinator.provider(for: ref.providerID) as? ClaudeProvider,
              var signals = try? await provider.extractSignals(for: ref) else { return }
        signals = signalExtractor.enrich(signals)

        // Gate check
        let currentSource = titleStore.currentTitle(for: ref.sessionID)?.source
        guard titleStrategy.shouldGenerateFirstTitle(for: signals) else {
            // Only write placeholder if no title yet or existing is already placeholder.
            // Never downgrade a real .rule title to placeholder.
            if currentSource == nil || currentSource == .placeholder {
                if let placeholder = titleStrategy.generatePlaceholderTitle(from: signals) {
                    titleStore.setTitle(for: ref.sessionID, title: placeholder)
                }
            }
            return
        }

        let title = titleStrategy.generateTitle(from: signals)
        titleStore.setTitle(for: ref.sessionID, title: title)

        let progress = titleStrategy.extractLastProgress(from: signals)
        titleStore.setLastProgress(for: ref.sessionID, progress: progress)
    }

    @MainActor
    public func cachedHistoryTexts(for sessionID: String) -> [String] {
        historyTextsCache[sessionID] ?? []
    }

    @MainActor
    public var visibleSessions: [SessionSummary] {
        sessions.filter { !archiveStore.isArchived($0.ref) || showArchived }
    }

    @MainActor
    public func relations(for ref: SessionRef) -> [SessionRelation] {
        let session = visibleSessions.first { $0.ref == ref }
        guard let session else { return [] }

        var relations: [SessionRelation] = []

        for other in visibleSessions where other.ref != ref {
            // Same project (cwd match)
            guard session.cwd != nil && session.cwd == other.cwd else { continue }

            // Same branch
            if let b1 = session.branch, let b2 = other.branch, b1 == b2 {
                relations.append(SessionRelation(otherSessionID: other.ref.sessionID, type: .sameBranch))
            }

            // Continuation: other ended within 2 hours before this one started
            let gap = session.createdAt.timeIntervalSince(other.lastActiveAt)
            if gap > 0 && gap < 7200 {
                relations.append(SessionRelation(otherSessionID: other.ref.sessionID, type: .continuation))
            }
        }

        return relations
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
                contextUsage: session.contextUsage,
                smartTitle: session.smartTitle,
                lastProgress: session.lastProgress,
                entrypoint: session.entrypoint
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

    // MARK: - LLM Enhancement

    /// LLM-enhance a single session. User-triggered only.
    @MainActor
    public func enhanceWithLLM(for ref: SessionRef) async throws {
        settings.ensureApiKeyLoaded()
        guard settings.llmConfig.isConfigured else {
            throw LLMClient.LLMError.notConfigured
        }
        guard let provider = await coordinator.provider(for: ref.providerID) as? ClaudeProvider,
              let inputs = try? await provider.extractEnhanceInputs(for: ref) else { return }
        // Full-scan signals (including jsonl-derived historyDisplayTexts
        // fallback) are then enriched with tasks/ and, if present,
        // ~/.claude/history.jsonl rows (which take precedence when non-empty).
        let signals = signalExtractor.enrich(inputs.signals)
        let rawTurns = inputs.rawTurns

        let session = sessions.first { $0.ref == ref }
        let lastActiveAt = session?.lastActiveAt ?? Date()

        let enhancer = LLMEnhancer(config: settings.llmConfig)
        guard let snapshot = await enhancer.enhance(signals: signals, rawTurns: rawTurns, basedOnLastActiveAt: lastActiveAt) else { return }
        understandingStore.setSnapshot(snapshot)
    }

    /// LLM-enhance a specific list of sessions. User-triggered only.
    /// Takes explicit [SessionRef] — caller decides scope (visible list, selection, etc.)
    @MainActor
    public func batchEnhanceLLM(sessions refs: [SessionRef]) async -> Int {
        settings.ensureApiKeyLoaded()
        guard settings.llmConfig.isConfigured else { return 0 }

        // Filter to candidates (sessions that need enhancement) before starting
        let candidates = refs.filter { ref in
            let session = sessions.first { $0.ref == ref }
            let lastActive = session?.lastActiveAt ?? Date()
            let hasFresh = understandingStore.hasEnhancement(for: ref.sessionID)
                && !understandingStore.isStale(for: ref.sessionID, lastActiveAt: lastActive)
            return !hasFresh
        }

        guard !candidates.isEmpty else { return 0 }

        batchProgress = (0, candidates.count)
        defer { batchProgress = nil }

        var enhanced = 0
        let total = candidates.count
        for ref in candidates {
            do {
                try await enhanceWithLLM(for: ref)
                enhanced += 1
                batchProgress = (enhanced, total)
                // Rate limit between API calls
                try? await Task.sleep(for: .milliseconds(500))
            } catch {
                continue
            }
        }
        return enhanced
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
