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
    /// V1 understanding storage. Kept for dual-write compatibility during
    /// v0.2.9. Will become read-only / removed in a later PR after V2 is
    /// proven across P1/P2/P3.
    public let understandingStore: UnderstandingStore
    /// V2 versioned understanding storage (v0.2.9, P1).
    public let understandingV2: UnderstandingStoreV2
    /// Read-only adapter over V1 file as legacy baseline source (v0.2.9, P1).
    public let legacyAdapter: LegacyUnderstandingAdapter
    /// Pure resolver for v0.2.9 display precedence (v0.2.9, P1).
    public let displayPolicy: UnderstandingDisplayPolicy
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
                understandingStore: UnderstandingStore = UnderstandingStore(),
                understandingV2: UnderstandingStoreV2 = UnderstandingStoreV2(),
                legacyAdapter: LegacyUnderstandingAdapter = LegacyUnderstandingAdapter(),
                displayPolicy: UnderstandingDisplayPolicy = UnderstandingDisplayPolicy()) {
        self.coordinator = coordinator
        self.labelStore = labelStore
        self.archiveStore = archiveStore
        self.settings = settings
        self.titleStore = titleStore
        self.signalExtractor = signalExtractor
        self.titleStrategy = titleStrategy
        self.understandingStore = understandingStore
        self.understandingV2 = understandingV2
        self.legacyAdapter = legacyAdapter
        self.displayPolicy = displayPolicy
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

    // MARK: - v0.2.9 resolved field accessors
    //
    // Convenience entry points that join V2 state, legacy snapshot, and
    // rule-layer fallbacks in a single call. Views consume `ResolvedField`
    // and render source chips / staleness from it.

    /// Resolves the current title for a session via the v0.2.9 display
    /// policy: Manual(v2) > AI(v2) > Legacy.title > Rule > UUID prefix.
    @MainActor
    public func resolvedTitle(for ref: SessionRef) -> ResolvedField {
        let sid = ref.sessionID
        let session = sessions.first { $0.ref == ref }
        let ruleTitle = ruleTitleFallback(for: sid, session: session)
        return displayPolicy.resolveTitle(
            state: understandingV2.state(for: sid),
            legacy: legacyAdapter.legacySnapshot(for: sid),
            ruleTitle: ruleTitle,
            sessionIDForFallback: sid
        )
    }

    /// Resolves the current progress for a session via the v0.2.9 display
    /// policy: Manual(v2) > AI(v2) > Legacy.progress > Rule/derived.
    @MainActor
    public func resolvedProgress(for ref: SessionRef) -> ResolvedField {
        let sid = ref.sessionID
        let session = sessions.first { $0.ref == ref }
        let ruleProgress = titleStore.lastProgress(for: sid) ?? session?.currentTaskSummary
        return displayPolicy.resolveProgress(
            state: understandingV2.state(for: sid),
            legacy: legacyAdapter.legacySnapshot(for: sid),
            ruleProgress: ruleProgress
        )
    }

    /// Resolves the current summary for a session via the v0.2.9 display
    /// policy: AI(v2) > Legacy.summary > nil. No manual path.
    @MainActor
    public func resolvedSummary(for ref: SessionRef) -> ResolvedField {
        let sid = ref.sessionID
        return displayPolicy.resolveSummary(
            state: understandingV2.state(for: sid),
            legacy: legacyAdapter.legacySnapshot(for: sid)
        )
    }

    /// Source-aware metadata for the AI panel's bottom row.
    ///
    /// Only consults V1 snapshot (and its `basedOnLastActiveAt`-driven
    /// stale signal) when the resolved fields show V2 has taken
    /// ownership (any title/progress/summary source is `.ai` or
    /// `.manual`). Legacy-only baselines route through `legacyAdapter`
    /// and force `isStale = false`, matching `StaleState.legacyUnknown`
    /// — legacy carries no trustworthy staleness claim.
    ///
    /// Returns nil when no AI / legacy content exists.
    @MainActor
    public func resolvedMetadata(for ref: SessionRef) -> ResolvedMetadata? {
        let sid = ref.sessionID
        let titleR = resolvedTitle(for: ref)
        let progressR = resolvedProgress(for: ref)
        let summaryR = resolvedSummary(for: ref)
        let sources = [titleR.source, progressR.source, summaryR.source]
        let hasV2Ownership = sources.contains { $0 == .ai || $0 == .manual }
        let hasLegacyCurrent = sources.contains { $0 == .legacy }

        let session = sessions.first { $0.ref == ref }
        let lastActive = session?.lastActiveAt ?? Date()

        if hasV2Ownership {
            // V2 has taken ownership of at least one field. Pick the
            // freshest signal between V1 snapshot and the latest V2 AI
            // artifact that is *currently displayed* (i.e. one of the
            // resolved fields' artifactIDs). Per-field regenerate is
            // V2-only (P2 C2), so V1 may lag behind a recent V2 write —
            // panel metadata must reflect the newer source. But an
            // unadopted AI candidate sitting in the chain while a manual
            // pointer wins must NOT surface its metadata, because the
            // visible field is still the manual value.
            let currentAIArtifactIDs: [UUID] = [titleR, progressR, summaryR]
                .filter { $0.source == .ai }
                .compactMap { $0.artifactID }
            let v1 = understandingStore.snapshot(for: sid)
            let v2Latest = latestCurrentV2AIArtifact(
                for: sid,
                currentAIArtifactIDs: currentAIArtifactIDs
            )

            switch (v1, v2Latest) {
            case (let v1?, let v2?):
                if v2.createdAt > v1.generatedAt {
                    // V2 is newer — per-field regenerate after full enhance.
                    return ResolvedMetadata(
                        model: v2.modelName ?? "?",
                        time: v2.createdAt,
                        isStale: lastActive > v2.createdAt
                    )
                }
                // V1 is newer or contemporaneous — use V1's full-fidelity
                // basedOnLastActiveAt-driven stale signal.
                return ResolvedMetadata(
                    model: v1.modelName,
                    time: v1.generatedAt,
                    isStale: understandingStore.isStale(for: sid, lastActiveAt: lastActive)
                )
            case (let v1?, nil):
                return ResolvedMetadata(
                    model: v1.modelName,
                    time: v1.generatedAt,
                    isStale: understandingStore.isStale(for: sid, lastActiveAt: lastActive)
                )
            case (nil, let v2?):
                return ResolvedMetadata(
                    model: v2.modelName ?? "?",
                    time: v2.createdAt,
                    isStale: lastActive > v2.createdAt
                )
            case (nil, nil):
                return nil
            }
        }

        if hasLegacyCurrent,
           let legacy = legacyAdapter.legacySnapshot(for: sid),
           let when = legacy.generatedAt {
            return ResolvedMetadata(
                model: legacy.modelName ?? "Legacy",
                time: when,
                isStale: false
            )
        }

        return nil
    }

    /// Returns the latest `.ai` artifact in `field`'s chain that is
    /// currently NOT selected by the pointer, when the resolved field
    /// has a `.manual` current source. Used by the panel to surface
    /// an "Adopt AI version" affordance.
    ///
    /// Returns nil when:
    /// - The session has no V2 state.
    /// - The resolved field's source is not `.manual` (no manual
    ///   override to compete against).
    /// - No `.ai` artifact exists in the chain.
    @MainActor
    public func unadoptedAICandidate(
        for ref: SessionRef,
        field: UnderstandingField
    ) -> UnderstandingArtifact? {
        let resolved: ResolvedField
        switch field {
        case .title:    resolved = resolvedTitle(for: ref)
        case .progress: resolved = resolvedProgress(for: ref)
        case .summary:  resolved = resolvedSummary(for: ref)
        }
        guard resolved.source == .manual else { return nil }
        guard let state = understandingV2.state(for: ref.sessionID) else { return nil }
        let chain: [UnderstandingArtifact]
        switch field {
        case .title:    chain = state.titleVersions
        case .progress: chain = state.progressVersions
        case .summary:  chain = state.summaryVersions
        }
        return chain.reversed().first(where: { $0.source == .ai })
    }

    /// Resolved staleness for a field, applying P3 derivation rules over
    /// the resolved field's source / stored staleState plus the session's
    /// `lastActiveAt`. Mirrors the rules in
    /// `UnderstandingDisplayPolicy.staleStateBy(...)`:
    ///
    /// 1. Legacy → `.legacyUnknown` (never derived stale).
    /// 2. Stored `.stalePartial(reason)` preserved as-is.
    /// 3. Stored `.fresh` + `lastActiveAt > artifact.createdAt` → derive
    ///    `.staleSessionUpdated(at: lastActiveAt)` at read time.
    /// 4. Else → `.fresh`.
    @MainActor
    public func resolvedStaleState(
        for ref: SessionRef,
        field: UnderstandingField
    ) -> StaleState {
        let resolved: ResolvedField
        switch field {
        case .title:    resolved = resolvedTitle(for: ref)
        case .progress: resolved = resolvedProgress(for: ref)
        case .summary:  resolved = resolvedSummary(for: ref)
        }

        let session = sessions.first { $0.ref == ref }
        let lastActive = session?.lastActiveAt
        let createdAt = resolvedArtifactCreatedAt(for: ref, field: field, resolved: resolved)

        return displayPolicy.staleStateBy(
            resolvedSource: resolved.source,
            storedStale: resolved.staleState,
            artifactCreatedAt: createdAt,
            sessionLastActiveAt: lastActive
        )
    }

    /// Humanized staleness explanation for the panel's per-field
    /// explanation line. Returns nil for `.fresh` (no explanation needed)
    /// and a Chinese-language string otherwise. Composes
    /// `resolvedStaleState` + the field's artifact `createdAt` and
    /// delegates the text mapping to
    /// `UnderstandingDisplayPolicy.explanation(...)`.
    @MainActor
    public func resolvedStaleExplanation(
        for ref: SessionRef,
        field: UnderstandingField
    ) -> String? {
        let stale = resolvedStaleState(for: ref, field: field)
        let session = sessions.first { $0.ref == ref }
        let lastActive = session?.lastActiveAt ?? Date()
        let resolved: ResolvedField
        switch field {
        case .title:    resolved = resolvedTitle(for: ref)
        case .progress: resolved = resolvedProgress(for: ref)
        case .summary:  resolved = resolvedSummary(for: ref)
        }
        let generatedAt = resolvedArtifactCreatedAt(for: ref, field: field, resolved: resolved) ?? lastActive
        return displayPolicy.explanation(
            for: stale,
            lastActiveAt: lastActive,
            generatedAt: generatedAt
        )
    }

    /// Looks up the V2 chain artifact's `createdAt` for `field`, given a
    /// pre-resolved field. Returns nil if no V2 artifact backs the
    /// resolved value (legacy / rule / uuidPrefix / none sources).
    @MainActor
    private func resolvedArtifactCreatedAt(
        for ref: SessionRef,
        field: UnderstandingField,
        resolved: ResolvedField
    ) -> Date? {
        guard let id = resolved.artifactID,
              let state = understandingV2.state(for: ref.sessionID)
        else { return nil }
        let chain: [UnderstandingArtifact]
        switch field {
        case .title:    chain = state.titleVersions
        case .progress: chain = state.progressVersions
        case .summary:  chain = state.summaryVersions
        }
        return chain.first(where: { $0.id == id })?.createdAt
    }

    /// Per-field chronological history for the v0.2.9 history drawer.
    ///
    /// Returns artifacts (each carrying an `isCurrent` flag), selection
    /// events for the requested field, and an optional legacy baseline
    /// row, all interleaved by timestamp.
    ///
    /// - Legacy entries appear only when the legacy snapshot has a
    ///   non-empty value for `field`.
    /// - An artifact is marked current when its ID matches the resolved
    ///   field's `artifactID` (delegating "what's current" to the display
    ///   policy so manual-vs-AI candidate semantics stay consistent).
    /// - Legacy is marked current when the resolved field's source is
    ///   `.legacy` (V2 has no artifact owning this field).
    /// - Legacy entries with a nil `generatedAt` sort to the chronological
    ///   start via `HistoryEntry.timestamp`'s `.distantPast` fallback.
    @MainActor
    public func fieldHistory(
        for ref: SessionRef,
        field: UnderstandingField
    ) -> [HistoryEntry] {
        let sid = ref.sessionID
        let state = understandingV2.state(for: sid)
        let legacy = legacyAdapter.legacySnapshot(for: sid)

        let resolved: ResolvedField
        switch field {
        case .title:    resolved = resolvedTitle(for: ref)
        case .progress: resolved = resolvedProgress(for: ref)
        case .summary:  resolved = resolvedSummary(for: ref)
        }

        let chain: [UnderstandingArtifact]
        let legacyValue: String?
        switch field {
        case .title:
            chain = state?.titleVersions ?? []
            legacyValue = legacy?.title
        case .progress:
            chain = state?.progressVersions ?? []
            legacyValue = legacy?.progress
        case .summary:
            chain = state?.summaryVersions ?? []
            legacyValue = legacy?.summary
        }

        var entries: [HistoryEntry] = []

        for artifact in chain {
            entries.append(.artifact(artifact, isCurrent: artifact.id == resolved.artifactID))
        }

        if let events = state?.selectionEvents {
            for event in events where event.field == field {
                entries.append(.selection(event))
            }
        }

        if let value = legacyValue, !value.isEmpty, let snap = legacy {
            entries.append(.legacy(snap, field: field, isCurrent: resolved.source == .legacy))
        }

        return entries.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.caseOrder != rhs.caseOrder {
                return lhs.caseOrder < rhs.caseOrder
            }
            return lhs.stableID < rhs.stableID
        }
    }

    /// v0.2.9 P4: pure-rule structural evidence for the panel section
    /// rendered below `LLMPanelView`. Composes a fresh `EvidencePackage`
    /// from the session's `SessionSummary` plus its computed relations.
    ///
    /// Returns an empty package when `ref` is not in `sessions[]` (e.g.
    /// the session was archived / removed between scans). All produced
    /// items are read-only structural data — no LLM calls, no async, no
    /// I/O beyond reading already-scanned in-memory state.
    ///
    /// See `docs/PLAN-v0.2.9-P4.md` C0 audit for the per-source binding
    /// decisions; the composer enforces them.
    @MainActor
    public func evidence(for ref: SessionRef) -> EvidencePackage {
        guard let session = sessions.first(where: { $0.ref == ref }) else {
            return EvidencePackage(items: [])
        }
        return EvidenceComposer.compose(
            session: session,
            relations: relations(for: ref)
        )
    }

    /// Returns the most recent `.ai` artifact among those currently
    /// displayed (i.e. ID is in `currentAIArtifactIDs`), or nil if no
    /// resolved field currently has an AI source. Unadopted AI
    /// candidates that sit in the chain but are not selected by any
    /// pointer are intentionally excluded — their metadata is not the
    /// metadata of what the user actually sees.
    @MainActor
    private func latestCurrentV2AIArtifact(
        for sessionID: String,
        currentAIArtifactIDs: [UUID]
    ) -> UnderstandingArtifact? {
        guard !currentAIArtifactIDs.isEmpty,
              let state = understandingV2.state(for: sessionID)
        else { return nil }
        let pool = state.titleVersions + state.progressVersions + state.summaryVersions
        return pool
            .filter { currentAIArtifactIDs.contains($0.id) }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    /// Composes the rule-layer title fallback: smart title (TitleStore)
    /// or, if absent, the cleaned raw session title. Returns nil if both
    /// would be empty so the policy walks down to UUID prefix.
    @MainActor
    private func ruleTitleFallback(for sid: String, session: SessionSummary?) -> String? {
        if let smart = titleStore.currentTitle(for: sid)?.text, !smart.isEmpty {
            return smart
        }
        guard let session else { return nil }
        let cleaned = RuleTitleStrategy.normalizeText(session.title)
        return cleaned.isEmpty ? nil : cleaned
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
        persistEnhancement(snapshot)
    }

    // MARK: - v0.2.9 P2 — manual edit + adopt

    /// Append a `.manual` title artifact and move the current pointer
    /// to it. Trims whitespace; empty values are a no-op. If the
    /// session has a current rationale, marks it `.stalePartial` since
    /// the rationale's basis is no longer current.
    @MainActor
    public func editTitle(for ref: SessionRef, newValue: String) {
        appendManualEdit(for: ref, field: .title, newValue: newValue, reason: "title edited")
    }

    /// Append a `.manual` progress artifact and move the current
    /// pointer to it. Same semantics as `editTitle(for:newValue:)`.
    @MainActor
    public func editProgress(for ref: SessionRef, newValue: String) {
        appendManualEdit(for: ref, field: .progress, newValue: newValue, reason: "progress edited")
    }

    @MainActor
    private func appendManualEdit(
        for ref: SessionRef,
        field: UnderstandingField,
        newValue: String,
        reason: String
    ) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let artifact = UnderstandingArtifact(
            value: trimmed,
            source: .manual,
            trigger: .manualEdit
        )
        understandingV2.appendArtifact(for: ref.sessionID, field: field, artifact)
        understandingV2.setRationaleStaleState(
            for: ref.sessionID,
            .stalePartial(reason: reason)
        )
    }

    /// Switch the current pointer for `field` to an existing AI
    /// artifact identified by `versionID`. The artifact must already
    /// be present in the chain and have `source == .ai`. Records a
    /// `SelectionEvent(action: .adopt, previousVersionID:targetVersionID:)`.
    /// **No new artifact is created.**
    ///
    /// Throws:
    /// - `StoreError.versionNotFound` if `versionID` is not in the chain
    ///   (or the session has no V2 state at all)
    /// - `StoreError.versionNotAI` if `versionID` exists in the chain
    ///   but its source is not `.ai` (manual / rule artifacts are not
    ///   adoptable; this is distinct from "unknown id")
    @MainActor
    public func adoptAIVersion(
        for ref: SessionRef,
        field: UnderstandingField,
        versionID: UUID
    ) throws {
        let sid = ref.sessionID
        guard let state = understandingV2.state(for: sid) else {
            throw UnderstandingStoreV2.StoreError.versionNotFound(field: field, id: versionID)
        }

        let chain: [UnderstandingArtifact]
        let previousPointer: UUID?
        switch field {
        case .title:
            chain = state.titleVersions
            previousPointer = state.currentTitleVersionID
        case .progress:
            chain = state.progressVersions
            previousPointer = state.currentProgressVersionID
        case .summary:
            chain = state.summaryVersions
            previousPointer = state.currentSummaryVersionID
        }

        guard let target = chain.first(where: { $0.id == versionID }) else {
            throw UnderstandingStoreV2.StoreError.versionNotFound(field: field, id: versionID)
        }
        guard target.source == .ai else {
            throw UnderstandingStoreV2.StoreError.versionNotAI(field: field, id: versionID)
        }

        try understandingV2.setCurrentPointer(for: sid, field: field, to: versionID)
        understandingV2.appendSelectionEvent(
            for: sid,
            SelectionEvent(
                field: field,
                action: .adopt,
                previousVersionID: previousPointer,
                targetVersionID: versionID
            )
        )
    }

    /// Persist an AI-generated snapshot with dual-write semantics:
    /// - V1: existing `UnderstandingStore.setSnapshot` (preserves downgrade
    ///   compatibility — pre-v0.2.9 builds keep reading current data).
    /// - V2: funneled through `appendAIArtifact` for title + (optional)
    ///   progress + (optional) summary. Pointer movement follows the C2
    ///   rules (manual override, if any, is preserved).
    ///
    /// Either write may fail independently; failures are best-effort and
    /// do not throw, matching the existing v0.2.7+ behavior.
    @MainActor
    func persistEnhancement(_ snapshot: LLMUnderstandingSnapshot) {
        // V1 dual-write (existing path)
        understandingStore.setSnapshot(snapshot)

        // V2 dual-write — every AI write goes through the appendAIArtifact seam.
        let sid = snapshot.sessionID
        appendAIArtifact(
            for: sid,
            field: .title,
            value: snapshot.title,
            modelName: snapshot.modelName,
            generatedAt: snapshot.generatedAt
        )
        if let progress = snapshot.progress, !progress.isEmpty {
            appendAIArtifact(
                for: sid,
                field: .progress,
                value: progress,
                modelName: snapshot.modelName,
                generatedAt: snapshot.generatedAt
            )
        }
        if let summary = snapshot.summary, !summary.isEmpty {
            appendAIArtifact(
                for: sid,
                field: .summary,
                value: summary,
                modelName: snapshot.modelName,
                generatedAt: snapshot.generatedAt
            )
        }
    }

    // MARK: - v0.2.9 P2 — per-field regenerate

    /// Regenerate a single field (title) via one LLM call. V2-only:
    /// V1 dual-write is intentionally skipped for per-field regenerate
    /// to avoid synthesizing placeholder values for the other two
    /// fields. Pointer movement follows C2 rules — manual override is
    /// preserved.
    @MainActor
    public func regenerateTitle(for ref: SessionRef) async throws {
        try await regenerateField(.title, for: ref)
    }

    @MainActor
    public func regenerateProgress(for ref: SessionRef) async throws {
        try await regenerateField(.progress, for: ref)
    }

    @MainActor
    public func regenerateSummary(for ref: SessionRef) async throws {
        try await regenerateField(.summary, for: ref)
    }

    @MainActor
    private func regenerateField(_ field: UnderstandingField, for ref: SessionRef) async throws {
        settings.ensureApiKeyLoaded()
        guard settings.llmConfig.isConfigured else {
            throw LLMClient.LLMError.notConfigured
        }
        guard let provider = await coordinator.provider(for: ref.providerID) as? ClaudeProvider,
              let inputs = try? await provider.extractEnhanceInputs(for: ref) else { return }
        let signals = signalExtractor.enrich(inputs.signals)

        let session = sessions.first { $0.ref == ref }
        let lastActiveAt = session?.lastActiveAt ?? Date()

        let enhancer = LLMEnhancer(config: settings.llmConfig)
        guard let result = await enhancer.enhanceField(
            field,
            signals: signals,
            rawTurns: inputs.rawTurns,
            basedOnLastActiveAt: lastActiveAt
        ) else { return }

        appendAIArtifact(
            for: ref.sessionID,
            field: result.field,
            value: result.value,
            modelName: result.modelName,
            generatedAt: result.generatedAt
        )
    }

    /// Persistence-only seam: every AI artifact write — full enhance,
    /// per-field regenerate, and (in tests) synthesized values — goes
    /// through this method. Tests can call it directly to exercise
    /// pointer-rule behavior without depending on a real LLM.
    ///
    /// Internal access — production code paths should call the public
    /// `regenerate*` or `enhanceWithLLM` methods.
    @MainActor
    func appendAIArtifact(
        for sessionID: String,
        field: UnderstandingField,
        value: String,
        modelName: String,
        generatedAt: Date
    ) {
        let artifact = UnderstandingArtifact(
            value: value,
            source: .ai,
            trigger: .manualGenerate,
            createdAt: generatedAt,
            staleState: .fresh,
            modelName: modelName
        )
        understandingV2.appendArtifact(for: sessionID, field: field, artifact)
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
