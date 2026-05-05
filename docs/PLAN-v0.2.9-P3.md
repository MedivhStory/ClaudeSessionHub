# P3 Implementation Note rev.3 — Staleness UI + History drawer

**Acceptance**: PLAN-v0.2.9.md §8 + P3 exit criteria — "Field-level staleness explanation displayed; history drawer accessible per field showing artifacts + selection events; stale → regenerate works."

## Files to modify

- `Services/SessionStore.swift` — read-only `fieldHistory(for:field:) -> [HistoryEntry]` (chronological, with current flag); `resolvedStaleState(for:field:) -> StaleState` (rules below).
- `Services/UnderstandingDisplayPolicy.swift` — pure derivation `staleStateBy(resolvedSource:storedStale:artifactCreatedAt:sessionLastActiveAt:)`; pure humanizer `explanation(for:lastActiveAt:generatedAt:)`.
- `Views/Sessions/LLMPanelView.swift` — visible "⚠ 已过期" / "Pre-v0.2.9 旧基线" badge text next to SourceChip; explanation rendered as small inline secondary text below the row (never hover-only). Per-field regenerate icon stays the refresh CTA — enabled whenever LLM is configured, no chain dependency.
- `ClaudeSessionHub.xcodeproj/project.pbxproj` — for new files.

## Files to add

- `Models/UnderstandingHistoryEntry.swift`

  ```swift
  enum HistoryEntry {
      case artifact(UnderstandingArtifact, isCurrent: Bool)
      case selection(SelectionEvent)
      case legacy(LegacyUnderstandingSnapshot, field: UnderstandingField, isCurrent: Bool)
  }
  ```

  with computed timestamp (legacy uses `generatedAt ?? .distantPast`).

- `Views/Sessions/UnderstandingHistoryDrawer.swift` — sheet/popover, chronological entries, "Pre-v0.2.9 baseline" legacy row, "currently selected" mark, staleness explanation banner. Read-only.
- `Tests/XCTests/Services/SessionStoreFieldHistoryTests.swift` — interleaving, current flag, legacy row presence/absence, ordering with nil `legacy.generatedAt`.
- `Tests/XCTests/Services/StaleStateDerivationTests.swift` — derivation rules.
- `Tests/XCTests/Services/StaleStateExplanationTests.swift` — humanizer per case.

## Staleness derivation (no new persisted fields)

`resolvedStaleState(for:field:)` resolves in this order:

1. **Legacy first** — if resolved source is `.legacy` → always `.legacyUnknown`. Never derive `.staleSessionUpdated` for legacy. Old sessions can only say "this is a baseline", never "this is stale".
2. **Stored partial preserved** — if the current artifact's `staleState` is `.stalePartial(reason)` → return as-is (set by P2 edit flows; P3 only renders the explanation, does not invent new cross-field dependencies).
3. **Stored fresh + session drift** — if stored is `.fresh` and `sessionLastActiveAt > artifact.createdAt` → derive `.staleSessionUpdated(at: sessionLastActiveAt)` at read time.
4. **Else** → `.fresh`.

## Humanizer mapping

| StaleState | Explanation text |
|---|---|
| `.fresh` | nil (no explanation needed) |
| `.staleSessionUpdated(at:)` | "会话在生成后又更新了 N 小时,此字段可能不再可信" |
| `.stalePartial(reason)` | "此字段标注为 stale: {reason}" (renders whatever P2 wrote) |
| `.legacyUnknown` | "Pre-v0.2.9 旧基线,无法判断时效" |

## Cross-field independence (explicit)

P3 does **not** add cross-field staleness propagation. Editing the title does not automatically mark progress or summary stale. P2 only writes `.stalePartial` on the rationale slot; P3 surfaces whatever staleness is already stored and the session-drift derivation per field — nothing more.

## Acceptance mapping

| §8 / P3 item | Test |
|---|---|
| Visible stale badge + visible explanation (no hover) | `StaleStateExplanationTests` + C4 UI smoke |
| Legacy → `.legacyUnknown` only, never derived stale | `StaleStateDerivationTests.testLegacyAlwaysLegacyUnknownEvenWithOldGeneratedAt` |
| Stored `.stalePartial` preserved (not overridden by derivation) | `testStoredPartialStaleNotOverriddenByDerivation` |
| Session-drift derivation for AI/manual current | `testSessionUpdatedAfterArtifactDerivesStale` |
| Regenerate refreshes including legacy/stale (gated only on `isConfigured`) | `testRegenerateOnStaleLegacySessionAppendsAIArtifact` |
| History drawer chronological + current flag + legacy row | `SessionStoreFieldHistoryTests` |
| Adopt event visible in drawer | reuses P2 fixture |

## Stays out of P3

Evidence layer (P4), rationale generation/storage (P7), long-session input + prompt rewrite (P5), desensitization + real-sample fixtures (P6). No new persisted fields; staleness is runtime-derivable.

## Commits (each dual-build verified)

- **C1** HistoryEntry model (artifact / selection / legacy) + `SessionStore.fieldHistory(...)` + tests.
- **C2** `staleStateBy(...)` derivation (legacy-first rule) + `explanation(...)` + `SessionStore.resolvedStaleState(...)` + tests.
- **C3** `UnderstandingHistoryDrawer` view + `LLMPanelView` history button per row + legacy row rendering.
- **C4** Stale badge text + explanation line on each field row; per-field regenerate enabled whenever LLM configured.

## C4 smoke checklist

1. **Stale-by-drift**: open a session whose `lastActiveAt` is after the AI title's `createdAt` → title row shows "⚠ 已过期" + explanation; no hover required.
2. **Stale-clear**: click per-field regenerate on that row → badge disappears or shows `.fresh`.
3. **Legacy session**: open a Pre-v0.2.9 baseline session → drawer shows legacy baseline row; badge text is the `legacyUnknown` explanation, NOT "已过期".
4. **Stored-partial render**: construct (via test seed or existing data) a field with `.stalePartial(reason: "...")` → row shows the stored reason as explanation. Editing title does NOT mark progress/summary stale; only the existing stored partial is rendered.
