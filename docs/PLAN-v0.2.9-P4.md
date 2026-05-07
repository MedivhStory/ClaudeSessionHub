# P4 Implementation Note rev.3 — Evidence layer

**Acceptance**: PLAN-v0.2.9.md §9 + §14 P4 exit — "AI panel shows evidence section. Constraint: pure rule, no LLM call from this PR." Items static text, read-only.

## Files to modify
- `Services/SessionStore.swift` — `evidence(for:) -> EvidencePackage` thin sync accessor
- `Views/Sessions/SessionTileView.swift` — embed `EvidencePanel` **below** `LLMPanelView` per §9
- `ClaudeSessionHub.xcodeproj/project.pbxproj`

## Files to add
- `Models/EvidenceItem.swift` — `EvidenceCategory` enum + `EvidenceItem { category, title, lines: [String] }` + `EvidencePackage` (ordered, omits empty)
- `Services/EvidenceComposer.swift` — pure `compose(session:relations:) -> EvidencePackage`; no I/O, no LLM, no async
- `Views/Sessions/EvidencePanel.swift` — `DisclosureGroup`, read-only, a11y ids per category
- `Tests/XCTests/Services/EvidenceComposerTests.swift`
- `Tests/XCTests/Services/SessionStoreEvidenceTests.swift`

## Sources (§9, structural only — verified by C0 audit before any code)
1. recent files · 2. recent tool ops · 3. time anchors (createdAt / lastActiveAt / milestone) · 4. branch + cwd · 5. related sessions · 6. project name · 7. current phase · 8. latest assistant progress

**Source 7 binding**: `current phase ← SessionSummary.taskPhase`; **omit category when `taskPhase == .unknown`**. Real model is non-optional `TaskPhase { inProgress, blocked, done, unknown }` — `.unknown` is the documented placeholder, not a missing value.

## Stays out of P4 (explicit)
- Rationale gen/storage → P7 · long-session input + prompt rewrite → P5 · desensitization → P6 · auto-trigger → not in v0.2.9
- LLM calls from evidence path — **HARD CONSTRAINT** per §9
- Editing evidence — read-only per §9
- New scanner / async load / new cache / new relation model — must reuse existing read-only entry points only

## Commits (each dual-build verified — `swift build` / `swift test` / `xcodebuild build` / `xcodebuild test`)
- **C0 — Pre-implementation audit, no code.** Fill `## C0 source audit` table on this note with columns `source · PLAN claim · current read path · sync? · decision · notes`. Per-row **decision** is exactly one of:
  - **usable now** — sync read-only entry exists on `main`; bind in C1 as-is.
  - **unavailable / degraded** — no sync entry · OR only coarser data than §9 · OR §9 fidelity would require new scanner / async / cache → P4 **omits the category** (or binds degraded value with explicit `notes`); MUST NOT add infrastructure.
  - **conflict with PLAN** — source name/semantics contradicts §9 · OR §9 fidelity forces new infrastructure PM may want re-scoped → **stop and ask PM before C1.**

  Source-not-found alone ≠ stop; mark `unavailable / degraded` and omit. Only PLAN-semantic mismatch (or new-infra question PM hasn't blessed) escalates.
- **C1** `EvidenceItem` / `EvidenceCategory` / `EvidencePackage` model + `EvidenceComposer.compose(...)` pure function + `EvidenceComposerTests` (per-source + empty omission, incl. `.unknown` taskPhase omission).
- **C2** `SessionStore.evidence(for:)` thin accessor + `SessionStoreEvidenceTests` (wiring through real `SessionSummary` + relations).
- **C3** `EvidencePanel` SwiftUI view + embed below `LLMPanelView` in `SessionTileView`. UI behavior covered by C4 smoke.
- **C4** Smoke checklist execution only — no code, no commits.

## Post-merge housekeeping (NOT in P4 commit order)
After P4 merge: open `chore/close-p4-doc` PR per R015 to add R011.a closure header to this file. Separate PR, separate CI run.

## C4 smoke checklist
1. Expanded tile of active session → evidence section visible below AI panel; categories populated.
2. Collapse/expand `DisclosureGroup` → state preserved per tile.
3. Session with nil branch / empty relations → those categories omitted (no empty rows).
4. Session with `.unknown` taskPhase → current phase category absent.
5. No network activity during evidence rendering.

---

## C0 source audit

Audit run on `feature/v0.2.9-p4-evidence` (parent: `main` @ `048b5bc`). Each row is graded `usable now` / `unavailable / degraded` / `conflict with PLAN` per rev.3 commit-order matrix. **No PLAN-semantic conflicts found** — all 8 sources resolved without escalation.

| # | source | PLAN claim | current read path | sync? | decision | notes |
|---|---|---|---|---|---|---|
| 1 | recent files | `SessionDetail.recentFiles` | `SessionDetail.recentFiles: [String]` defined at `Models/CanonicalModels.swift:86`; only obtainable via `provider.loadSessionDetail(for:)` (async, declared on `AgentProvider`). `SessionStore` does **not** cache `SessionDetail`. | ❌ async only | **unavailable / degraded** | Bind degraded sync value `SessionSummary.filesTouched: Int` (count). Render as one line `"<N> files touched"`. Adding sync detail cache = new infrastructure → ruled out by rev.3 §"Stays out of P4". |
| 2 | recent tool ops | `SessionSignals.toolsUsed` | `SessionSignals.toolsUsed: Set<String>` at `Models/SessionSignals.swift:29`; built only inside `generateTitlesForNewSessions` / `refreshTitle` via `provider.extractSignals(for:)` (async). `SessionStore` does **not** cache `SessionSignals`. | ❌ async only | **unavailable / degraded** | **Omit category** in P4. No sync coarser substitute exists in `SessionSummary`. Adding a `signalsByID` cache = new cache → ruled out. |
| 3 | time anchors | createdAt / lastActiveAt + milestone events | `SessionSummary.createdAt` / `SessionSummary.lastActiveAt` (`Models/CanonicalModels.swift:63-64`); milestones via pure `MilestoneSampler.sample(...)` (`Services/MilestoneSampler.swift`) over `SessionStore.cachedHistoryTexts(for:)` (sync, `Services/SessionStore.swift:145`). | ✅ sync | **usable now** | createdAt/lastActiveAt direct; milestones via existing pure sampler over already-cached history texts. No new I/O. |
| 4 | branch + cwd | `SessionSummary.cwd` / `branch` | `SessionSummary.cwd: String?` / `branch: String?` (`Models/CanonicalModels.swift:58-59`). | ✅ sync | **usable now** | Both optional; per smoke item 3 omit when nil/empty. |
| 5 | related sessions | `SessionStore.relations` | `SessionStore.relations(for: SessionRef) -> [SessionRelation]` (`Services/SessionStore.swift:510`). `SessionRelation = (otherSessionID, type ∈ sameBranch \| timeOverlap \| continuation)`. | ✅ sync | **usable now** | Already used by `SessionTileView` line 288/334. |
| 6 | project name | `ProjectNameResolver` | `ProjectNameResolver.displayName(for: cwd) -> String` (static, `Services/SessionStore.swift:902`). | ✅ sync | **usable now** | Pure. Omit when cwd nil. |
| 7 | current phase | `SessionSummary.taskPhase` | `SessionSummary.taskPhase: TaskPhase` (`Models/CanonicalModels.swift:57`); enum `{ inProgress, blocked, done, unknown }` (line 16-18), non-optional. | ✅ sync | **usable now** | Per rev.3 source-7 binding: omit when `.unknown`. |
| 8 | latest assistant progress | `lastAssistantProgress` | `SessionSignals.lastAssistantProgress: String?` exists (`Models/SessionSignals.swift:14`) but is async-built only. **Sync persisted equivalent**: `SessionSummary.lastProgress: String?` (`Models/CanonicalModels.swift:67`) — already used by `resolvedProgress` rule fallback at `SessionStore.swift:176`. | ✅ sync (via `SessionSummary.lastProgress`) | **usable now** | NAMING ALIAS, not semantic conflict — both express "last progress observed from assistant"; `SessionSummary.lastProgress` is the sync persisted form. C1 may cascade `lastProgress ?? currentTaskSummary` if more permissive coverage is wanted. |

### Audit decisions summary

- **6 of 8 sources `usable now`** (3, 4, 5, 6, 7, 8) → bind directly in C1.
- **2 of 8 sources `unavailable / degraded`** (1, 2) — both because their PLAN-named producers are async-only (`provider.loadSessionDetail` / `provider.extractSignals`) and `SessionStore` does not cache them; rev.3 forbids adding new caches/scanners.
  - Source 1: bind degraded count (`filesTouched: Int`) — keeps the recall signal at coarser fidelity.
  - Source 2: **omit category** entirely from P4. No coarser sync equivalent exists.
- **0 sources `conflict with PLAN`** — no PM escalation required.

### One product-impact note for PM (R007 default action)

Source 1 degradation drops file-list richness to a count line. Source 2 omission removes the "recent tool operations" category from the P4 evidence section entirely. Both are within rev.3's "P4 may omit / degrade rather than add infrastructure" envelope, but they reduce evidence richness vs. PLAN §9's full surface. **Default action: proceed with degrade-1 + omit-2 in C1 as graded above.** If PM wants either upgraded later, that's a follow-up infra PR (sync detail cache for source 1; sync signals cache for source 2) outside P4 scope — flag now if you want to re-scope. If no objection, C1 begins on PM go-ahead.
