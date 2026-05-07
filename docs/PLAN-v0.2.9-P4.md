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
