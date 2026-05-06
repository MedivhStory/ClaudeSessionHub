import Foundation

// MARK: - ResolvedSource

/// Source attribution for a resolved current value. Distinct cases for
/// each precedence layer so callers can render distinct UI chips.
public enum ResolvedSource: String, Sendable, Equatable, CaseIterable {
    /// V2 AI artifact (or v2 artifact whose `source == .ai`).
    case ai
    /// V2 manual artifact created by user edit.
    case manual
    /// Rule-layer fallback (passed in by caller from `RuleTitleStrategy`
    /// or session signals). Not a v2 artifact.
    case rule
    /// Pre-v0.2.9 legacy snapshot (read-only, no version chain).
    case legacy
    /// 8-character UUID prefix fallback for title only.
    case uuidPrefix
    /// No value available (summary or progress with nothing to show).
    case none
}

// MARK: - ResolvedMetadata

/// Source-aware AI panel metadata: which model produced the current
/// understanding, when, and whether it appears stale relative to the
/// session's `lastActiveAt`.
///
/// Composed by `SessionStore.resolvedMetadata(for:)` — the policy
/// itself does not produce this since metadata depends on V1 snapshot
/// vs V2 artifact selection logic that lives in the store.
public struct ResolvedMetadata: Sendable, Equatable {
    public let model: String
    public let time: Date
    public let isStale: Bool

    public init(model: String, time: Date, isStale: Bool) {
        self.model = model
        self.time = time
        self.isStale = isStale
    }
}

// MARK: - ResolvedField

/// Result of resolving a single understanding field (title, progress, or
/// summary) for display.
public struct ResolvedField: Sendable, Equatable {
    /// Display value. Nil only when `source == .none`.
    public let value: String?
    public let source: ResolvedSource
    /// Staleness from the underlying artifact when the source is a v2
    /// artifact. `.legacyUnknown` for legacy. Nil for rule, uuidPrefix,
    /// none.
    public let staleState: StaleState?
    /// V2 artifact ID when `source` resolves to a v2 artifact via either
    /// pointer or precedence. Nil otherwise.
    public let artifactID: UUID?
    /// True if `state.currentXVersionID` was set but did not resolve to
    /// any artifact in the chain. The resolved field still represents
    /// the precedence fallback in that case.
    public let invalidPointer: Bool

    public init(
        value: String?,
        source: ResolvedSource,
        staleState: StaleState? = nil,
        artifactID: UUID? = nil,
        invalidPointer: Bool = false
    ) {
        self.value = value
        self.source = source
        self.staleState = staleState
        self.artifactID = artifactID
        self.invalidPointer = invalidPointer
    }
}

// MARK: - UnderstandingDisplayPolicy

/// Pure functional resolver for v0.2.9 display precedence.
///
/// No I/O, no persistence, no UI access. Caller provides the v2 state,
/// the legacy snapshot, the rule fallback values, and (for title) a
/// session ID for the UUID prefix tail fallback.
///
/// Precedence:
/// - Title:    Manual(v2) > AI(v2) > Legacy.title > Rule > UUID prefix
/// - Progress: Manual(v2) > AI(v2) > Legacy.progress > Rule/derived
/// - Summary:  AI(v2) > Legacy.summary > nil (no manual path)
public struct UnderstandingDisplayPolicy: Sendable {

    public init() {}

    // MARK: Title

    public func resolveTitle(
        state: UnderstandingState?,
        legacy: LegacyUnderstandingSnapshot?,
        ruleTitle: String?,
        sessionIDForFallback: String
    ) -> ResolvedField {
        let chain = state?.titleVersions ?? []
        switch resolvePointer(state?.currentTitleVersionID, in: chain) {
        case .resolved(let artifact):
            return resolved(from: artifact)
        case .invalidPointer:
            return titleFallback(
                chain: chain,
                legacy: legacy,
                ruleTitle: ruleTitle,
                sessionIDForFallback: sessionIDForFallback,
                invalidPointer: true
            )
        case .nilPointer:
            return titleFallback(
                chain: chain,
                legacy: legacy,
                ruleTitle: ruleTitle,
                sessionIDForFallback: sessionIDForFallback,
                invalidPointer: false
            )
        }
    }

    private func titleFallback(
        chain: [UnderstandingArtifact],
        legacy: LegacyUnderstandingSnapshot?,
        ruleTitle: String?,
        sessionIDForFallback: String,
        invalidPointer: Bool
    ) -> ResolvedField {
        if let manual = latest(in: chain, source: .manual) {
            return resolved(from: manual, invalidPointer: invalidPointer)
        }
        if let ai = latest(in: chain, source: .ai) {
            return resolved(from: ai, invalidPointer: invalidPointer)
        }
        if let title = legacy?.title, !title.isEmpty {
            return ResolvedField(
                value: title,
                source: .legacy,
                staleState: .legacyUnknown,
                invalidPointer: invalidPointer
            )
        }
        if let rule = ruleTitle, !rule.isEmpty {
            return ResolvedField(
                value: rule,
                source: .rule,
                invalidPointer: invalidPointer
            )
        }
        return ResolvedField(
            value: String(sessionIDForFallback.prefix(8)),
            source: .uuidPrefix,
            invalidPointer: invalidPointer
        )
    }

    // MARK: Progress

    public func resolveProgress(
        state: UnderstandingState?,
        legacy: LegacyUnderstandingSnapshot?,
        ruleProgress: String?
    ) -> ResolvedField {
        let chain = state?.progressVersions ?? []
        switch resolvePointer(state?.currentProgressVersionID, in: chain) {
        case .resolved(let artifact):
            return resolved(from: artifact)
        case .invalidPointer:
            return progressFallback(chain: chain, legacy: legacy, ruleProgress: ruleProgress, invalidPointer: true)
        case .nilPointer:
            return progressFallback(chain: chain, legacy: legacy, ruleProgress: ruleProgress, invalidPointer: false)
        }
    }

    private func progressFallback(
        chain: [UnderstandingArtifact],
        legacy: LegacyUnderstandingSnapshot?,
        ruleProgress: String?,
        invalidPointer: Bool
    ) -> ResolvedField {
        if let manual = latest(in: chain, source: .manual) {
            return resolved(from: manual, invalidPointer: invalidPointer)
        }
        if let ai = latest(in: chain, source: .ai) {
            return resolved(from: ai, invalidPointer: invalidPointer)
        }
        if let progress = legacy?.progress, !progress.isEmpty {
            return ResolvedField(
                value: progress,
                source: .legacy,
                staleState: .legacyUnknown,
                invalidPointer: invalidPointer
            )
        }
        if let rule = ruleProgress, !rule.isEmpty {
            return ResolvedField(
                value: rule,
                source: .rule,
                invalidPointer: invalidPointer
            )
        }
        return ResolvedField(value: nil, source: .none, invalidPointer: invalidPointer)
    }

    // MARK: Summary

    public func resolveSummary(
        state: UnderstandingState?,
        legacy: LegacyUnderstandingSnapshot?
    ) -> ResolvedField {
        let chain = state?.summaryVersions ?? []
        switch resolvePointer(state?.currentSummaryVersionID, in: chain) {
        case .resolved(let artifact):
            return resolved(from: artifact)
        case .invalidPointer:
            return summaryFallback(chain: chain, legacy: legacy, invalidPointer: true)
        case .nilPointer:
            return summaryFallback(chain: chain, legacy: legacy, invalidPointer: false)
        }
    }

    private func summaryFallback(
        chain: [UnderstandingArtifact],
        legacy: LegacyUnderstandingSnapshot?,
        invalidPointer: Bool
    ) -> ResolvedField {
        // Summary has no manual precedence path; only AI is consulted.
        if let ai = latest(in: chain, source: .ai) {
            return resolved(from: ai, invalidPointer: invalidPointer)
        }
        if let summary = legacy?.summary, !summary.isEmpty {
            return ResolvedField(
                value: summary,
                source: .legacy,
                staleState: .legacyUnknown,
                invalidPointer: invalidPointer
            )
        }
        return ResolvedField(value: nil, source: .none, invalidPointer: invalidPointer)
    }

    // MARK: - Helpers

    private enum PointerResolution {
        case nilPointer
        case resolved(UnderstandingArtifact)
        case invalidPointer
    }

    private func resolvePointer(
        _ pointer: UUID?,
        in chain: [UnderstandingArtifact]
    ) -> PointerResolution {
        guard let id = pointer else { return .nilPointer }
        if let artifact = chain.first(where: { $0.id == id }) {
            return .resolved(artifact)
        }
        return .invalidPointer
    }

    private func latest(
        in chain: [UnderstandingArtifact],
        source: UnderstandingSource
    ) -> UnderstandingArtifact? {
        chain.reversed().first(where: { $0.source == source })
    }

    private func resolved(
        from artifact: UnderstandingArtifact,
        invalidPointer: Bool = false
    ) -> ResolvedField {
        let resolvedSource: ResolvedSource
        switch artifact.source {
        case .ai:     resolvedSource = .ai
        case .manual: resolvedSource = .manual
        case .rule:   resolvedSource = .rule
        }
        return ResolvedField(
            value: artifact.value,
            source: resolvedSource,
            staleState: artifact.staleState,
            artifactID: artifact.id,
            invalidPointer: invalidPointer
        )
    }

    // MARK: - P3 C2: staleness derivation + humanizer

    /// Pure staleness derivation. See PLAN-v0.2.9-P3.md §"Staleness derivation".
    ///
    /// Rules in order:
    /// 1. **Legacy first** — `resolvedSource == .legacy` always returns
    ///    `.legacyUnknown`. Old sessions can claim "this is a baseline",
    ///    never "this is stale".
    /// 2. **Stored partial preserved** — a stored `.stalePartial(reason)`
    ///    is returned as-is. P2 edit flows write this; P3 only renders.
    /// 3. **Stored fresh + session drift** — when stored is `.fresh` and
    ///    `sessionLastActiveAt > artifactCreatedAt`, derive
    ///    `.staleSessionUpdated(at: sessionLastActiveAt)` at read time.
    /// 4. **Else** — `.fresh`.
    public func staleStateBy(
        resolvedSource: ResolvedSource,
        storedStale: StaleState?,
        artifactCreatedAt: Date?,
        sessionLastActiveAt: Date?
    ) -> StaleState {
        if resolvedSource == .legacy {
            return .legacyUnknown
        }
        if case .stalePartial(let reason)? = storedStale {
            return .stalePartial(reason: reason)
        }
        if case .fresh? = storedStale,
           let createdAt = artifactCreatedAt,
           let lastActive = sessionLastActiveAt,
           lastActive > createdAt {
            return .staleSessionUpdated(at: lastActive)
        }
        return .fresh
    }

    /// Pure humanizer. Returns nil for `.fresh` (no explanation needed) and
    /// a Chinese-language explanation otherwise.
    ///
    /// For `.staleSessionUpdated`, the displayed hour count is
    /// `floor((lastActiveAt - generatedAt) / 3600)` clamped to ≥ 1 so
    /// sub-hour drifts still render a non-zero gap.
    public func explanation(
        for stale: StaleState,
        lastActiveAt: Date,
        generatedAt: Date
    ) -> String? {
        switch stale {
        case .fresh:
            return nil
        case .staleSessionUpdated:
            let secs = lastActiveAt.timeIntervalSince(generatedAt)
            let hours = max(1, Int(secs / 3600))
            return "会话在生成后又更新了 \(hours) 小时,此字段可能不再可信"
        case .stalePartial(let reason):
            return "此字段标注为 stale: \(reason)"
        case .legacyUnknown:
            return "Pre-v0.2.9 旧基线,无法判断时效"
        }
    }
}
