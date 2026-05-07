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

## C4 smoke checklist (updated post-C3.1 — focus is de-dup, not "categories populated")
1. **No duplication with existing tile chrome**: in the expanded tile, the EvidencePanel must NOT render any of: recent files (QuickFacts owns it), time anchors (tile header owns it), branch + cwd / project name (metadata row owns it), related sessions (leftColumn owns it). C3.1 view-level filter drops these 5 categories before render.
2. **What CAN appear**: at most "当前阶段" and "最近进展" — the only two §9 categories not duplicated by other expanded-tile UI. If both also empty/`.unknown`, the entire EvidencePanel must hide (no header, no chrome).
3. Collapse/expand the `DisclosureGroup` → state preserved per tile (until tile itself collapses).
4. Session with `.unknown` taskPhase + empty progress → EvidencePanel renders nothing.
5. No network activity during evidence rendering (Console filter).

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

---

## Known build/surface ratio risk (post-C3.2 finding)

**Surfaced after C3 smoke and C3.1 de-dup.** P4's data layer ships 7 evidence categories (`recentFiles`, `timeAnchors`, `branchCwd`, `relatedSessions`, `projectName`, `currentPhase`, `latestProgress`) end-to-end (model + composer + store accessor + tests). The C3.2 expanded-tile filter intentionally drops 5 of those 7 because they duplicate higher-fidelity content already shown by other tile chrome (QuickFactsView / tile header / metadata row / leftColumn).

| Layer | Categories shipped | Categories actually rendered in expanded tile |
|---|---|---|
| Data (`EvidenceComposer` + `SessionStore.evidence(for:)`) | 7 | n/a |
| UI (`EvidencePanel` after expanded-tile filter) | n/a | up to 2 (`currentPhase` + `latestProgress`); often only `latestProgress` |

**Build-vs-surface ratio ≈ 7:1.** The other 5 categories are dormant infrastructure pending one of:

- **P5** prompt-input rewrite — may consume dormant categories as structured prompt context.
- **P7** rationale generation — may use the categories as rationale grounding.
- A future detail / inspector surface — if a non-tile host context wants to render the full canonical package, the C3.1 filter is opt-in (composer canonical package is unchanged).

### Required follow-up (tracking item)

- **Before P5 starts**: verify whether P5 will actually consume any of the 5 dormant categories. If yes, the data layer earns its keep retroactively. If no, the dormant categories should be **pruned** rather than carried into v0.3.
- **Re-evaluate at v0.2.9 GA / v0.3 kickoff**: if neither P5 nor P7 nor a new surface materializes the dormant categories, open a follow-up cleanup PR to prune them from `EvidenceCategory` + `EvidenceComposer` + their tests. Carrying unused infrastructure into v0.3 is the avoidable cost this section flags.
- **Process change for future phases**: the data-first slip that produced this ratio is the case study behind RULES.md R016 (UI-first phase note). P5 / P6 / P7 implementation notes will lead with "what does the user see" before listing files; P4 is grandfathered.
