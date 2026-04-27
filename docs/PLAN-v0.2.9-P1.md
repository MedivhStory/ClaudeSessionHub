# PLAN-v0.2.9-P1 — Data model + Display policy + Migration

**Created**: 2026-04-27
**Status**: Implementation planning (no code yet)
**Parent**: `docs/PLAN-v0.2.9.md` § P1
**Doc type**: State doc — covered by Doc Registry `docs/PLAN-v*.md`

---

## Goal

Make the v0.2.9 data model real: `understanding-v2.json` exists, V2 is the
new authoritative source, V1 stays in dual-write for compatibility, display
policy resolves precedence correctly, and minimal UI chips reflect source.
AI enhance keeps using existing UI buttons.

After P1:

- AI enhance writes to **both** V1 (existing path) and V2 (new path) —
  dual-write.
- V1 file (`understanding.json`) is still readable and writable; downgrade
  safe.
- V2 file (`understanding-v2.json`) is created and populated.
- Source chip visible per field for AI / 规则 / Legacy. Manual path
  validated by unit tests only (no edit UI in P1).
- Legacy sessions show "Pre-v0.2.9 baseline" chip until first regenerate.

---

## Design decisions

### 1. LLMEnhancer stays unchanged in P1

LLMEnhancer continues to return `LLMUnderstandingSnapshot`. SessionStore
wraps the snapshot into 3 V2 artifacts (`title`, `progress`, `summary`)
at write time, and also writes V1 via existing
`UnderstandingStore.setSnapshot(...)` (dual-write). Per-field regenerate,
rationale, prompt rewrite — all P5/P7 work.

### 2. Dual-write strategy: V1 write retained in P1

AI enhance writes to BOTH V1 and V2:

- V1 write keeps downgrade safe — if a user reverts to a pre-v0.2.9 build,
  the V1 file remains current.
- V2 write is the new source of truth for display policy.

Both writes succeed-or-fail independently. V1 write failure does not block
V2 write; V2 write failure does not block V1 write.

Removal of V1 write is **not** part of P1. It happens in a later PR (after
P1/P2/P3 prove V2 path is reliable). At that point, V1 becomes truly
read-only, and `UnderstandingStore.setSnapshot` calls are removed.

### 3. `UnderstandingStore.swift` stays in P1

Existing `UnderstandingStore` class is preserved. It continues to handle
V1 file persistence (read + write) for the dual-write path. Existing
`UnderstandingStoreTests.swift` stays, validating V1 behavior.

`LegacyUnderstandingAdapter` is added **alongside** `UnderstandingStore`,
not replacing it. The adapter reads `understanding.json` independently
via FileManager (no runtime dependency on `UnderstandingStore`), exposes
a read-only API producing `LegacyUnderstandingSnapshot`. This keeps the
future cleanup path simple — when V1 is removed, `UnderstandingStore`
can be deleted without touching the adapter.

### 4. `UnderstandingDisplayPolicy` is a pure functional resolver

Input: `UnderstandingState` (V2) + `LegacyUnderstandingSnapshot?` +
`SessionSummary` (for rule fallback).
Output: `ResolvedField` (value + source + staleState).

No I/O. No side effects. Easy to unit-test exhaustively.

### 5. SessionStore re-wired

- Keep `understandingStore: UnderstandingStore` (used for V1 dual-write).
- Add `understandingV2: UnderstandingStoreV2`.
- Add `legacyAdapter: LegacyUnderstandingAdapter`.
- Add `displayPolicy: UnderstandingDisplayPolicy` (pure).

Existing display-side callers of `understandingStore.snapshot(for:)`,
`hasEnhancement(for:)`, `isStale(for:lastActiveAt:)` migrate to
display-policy methods.

`enhanceWithLLM` writes V1 + V2 (dual-write).

### 6. V2 file format

```json
{
  "schemaVersion": "1",
  "states": {
    "<sessionID>": {
      "sessionID": "...",
      "titleVersions": [...],
      "currentTitleVersionID": "...",
      "progressVersions": [...],
      "currentProgressVersionID": "...",
      "summaryVersions": [...],
      "currentSummaryVersionID": "...",
      "selectionEvents": [...],
      "currentRationale": null
    }
  }
}
```

Legacy snapshot is NOT persisted in V2 file — it's derived from V1 file
at read time and joined into in-memory `UnderstandingState`.

### 7. P1 exposes V2 store primitives only; no SessionStore edit facade

V2 store methods (`appendArtifact`, `setCurrentPointer`,
`appendSelectionEvent`) are exercised by unit tests. P1 does NOT add
`SessionStore.editTitle()` or "Adopt" UI — those are P2.

---

## Files to add

| File | Purpose |
|------|---------|
| `Sources/ClaudeSessionHub/Models/UnderstandingArtifact.swift` | `UnderstandingSource`, `UnderstandingTrigger`, `StaleState`, `UnderstandingArtifact`, `UnderstandingField`, `SelectionAction`, `SelectionEvent`, `RationaleMetadata`, `LegacyUnderstandingSnapshot` |
| `Sources/ClaudeSessionHub/Models/UnderstandingState.swift` | `UnderstandingState` container |
| `Sources/ClaudeSessionHub/Services/UnderstandingStoreV2.swift` | Persistence at `understanding-v2.json`; `state(for:)`, `appendArtifact(...)`, `setCurrentPointer(...)`, `appendSelectionEvent(...)` |
| `Sources/ClaudeSessionHub/Services/LegacyUnderstandingAdapter.swift` | Read-only over `understanding.json` via FileManager; `legacySnapshot(for:)` returns `LegacyUnderstandingSnapshot?`; never writes |
| `Sources/ClaudeSessionHub/Services/UnderstandingDisplayPolicy.swift` | Pure resolver; `resolveTitle(state:legacy:summary:)`, `resolveProgress(...)`, `resolveSummary(...)` |
| `Tests/XCTests/Services/UnderstandingStoreV2Tests.swift` | V2 round-trip + pointer + event API |
| `Tests/XCTests/Services/LegacyUnderstandingAdapterTests.swift` | V1 read paths, missing file, partial fields, never-writes assertion |
| `Tests/XCTests/Services/UnderstandingDisplayPolicyTests.swift` | Precedence resolution, all combinations including manual paths |
| `Tests/XCTests/Services/UnderstandingMigrationTests.swift` | Hybrid migration scenarios end-to-end |

Mirror tests under `Tests/TestRunner/Services/` per dual-test-runner
convention.

---

## Files to modify

| File | Change |
|------|--------|
| `Sources/ClaudeSessionHub/Services/SessionStore.swift` | Add V2 store + legacy adapter + display policy properties; keep existing `understandingStore` for V1 dual-write; rewire display callers; `enhanceWithLLM` does V1 + V2 dual-write |
| `Sources/ClaudeSessionHub/Services/UnderstandingStore.swift` | **No changes**. Stays as V1 dual-write target |
| `Sources/ClaudeSessionHub/Views/Sessions/SessionTileView.swift` | `displayTitle` / `titleSource` / `bestSummary` use display policy; source chip extended to AI / 规则 / Legacy (manual case validated by tests, not realizable in UI during P1); legacy chip "Pre-v0.2.9 baseline" |
| `Sources/ClaudeSessionHub/Views/Sessions/LLMPanelView.swift` | Per-field source chip; legacy chip when current value is from legacy |
| `Sources/ClaudeSessionHub/App/ClaudeSessionHubApp.swift` | Init V2 store + legacy adapter; pass into SessionStore init |
| `ClaudeSessionHub.xcodeproj/project.pbxproj` | Updated **in the same commit** as each Swift file add — never deferred |

---

## Test coverage

### Migration scenarios (UnderstandingMigrationTests)

- V1 exists, V2 absent → V1 untouched in mtime (read-only access only via
  adapter), V2 created empty, legacy adapter exposes V1 data
- V1 exists, V2 exists → both readable, V2 wins per session per display
  policy; dual-write still updates both
- V1 absent, V2 exists → adapter returns nil legacy, V2 used
- Neither file → both empty, falls back to rule layer
- V1 partial (only title) → adapter exposes title, progress/summary nil
- After regenerate → both V1 and V2 updated (dual-write); legacy snapshot
  still readable

### Display precedence (UnderstandingDisplayPolicyTests)

For each field (title, progress, summary):

- nil pointer + empty state + nothing → rule fallback (or UUID for title,
  nil for summary)
- nil pointer + only legacy → legacy with `Legacy` source
- nil pointer + only AI artifact → AI
- nil pointer + AI + manual artifact → manual wins (manual > AI) —
  **unit test only; no UI path in P1**
- nil pointer + AI + legacy → AI wins (AI > legacy)
- pointer set to AI, manual exists → AI wins (pointer override) —
  **unit test only**
- pointer set to manual, newer AI exists → manual wins — **unit test only**
- summary: AI > legacy.summary > nil (no manual path; v0.2.9 has no
  summary edit)

### V2 store API (UnderstandingStoreV2Tests)

- Encode → decode → equal: state with multiple artifacts, with selection
  events, with no legacy (legacy not persisted in V2)
- `appendArtifact` AI when pointer nil → pointer auto-moves
- `appendArtifact` AI when pointer on AI → pointer auto-moves
- `appendArtifact` AI when pointer on manual → pointer does NOT move
  (candidate)
- `appendArtifact` manual edit → pointer auto-moves to new manual
- `setCurrentPointer` records correctly
- `appendSelectionEvent` records `previousVersionID` + `targetVersionID`
- Empty store encodes to valid JSON with `schemaVersion: "1"` + empty
  `states`

### Legacy adapter (LegacyUnderstandingAdapterTests)

- Reads existing `understanding.json` produced by v0.2.8.x format
- Missing file → returns nil for all sessions, no crash
- Partial v1 entries → optional fields propagate correctly
- Never writes: file mtime unchanged after multiple read calls
- `generatedAt`: present in V1 → non-nil on snapshot; absent → nil

---

## Constraints

- AI enhance writes to V1 (existing path) AND V2 (new path) — dual-write.
- V1 write removal is NOT part of P1; deferred to a later PR.
- Legacy adapter never writes.
- DisplayPolicy is pure (no I/O).
- LLMEnhancer is NOT modified.
- No edit UI, no per-field regenerate UI, no history drawer, no evidence
  layer, no rationale.
- xcodeproj membership updated in the same commit as Swift file changes.

---

## Internal commit sequence (within single P1 PR)

| # | Commit | Files | Verification |
|---|--------|-------|--------------|
| C1 | New model types | adds 2 Swift files + pbxproj | swift build + swift test + xcodebuild build |
| C2 | UnderstandingStoreV2 + tests | adds 2 Swift files + pbxproj | full 4-way verification |
| C3 | LegacyUnderstandingAdapter + tests | adds 2 Swift files + pbxproj | full 4-way verification |
| C4 | UnderstandingDisplayPolicy + tests | adds 2 Swift files + pbxproj | full 4-way verification |
| C5 | SessionStore dual-write wiring + ClaudeSessionHubApp init + UnderstandingMigrationTests | modifies existing + adds 1 test file + pbxproj | full 4-way verification |
| C6 | View layer migration + source chip + legacy chip | modifies views | full 4-way verification |

Six commits. Every commit that adds or removes a Swift file updates
pbxproj atomically.

---

## Acceptance criteria

P1 is done when:

- All 4 verification steps pass on every commit: `swift build`,
  `swift test`, `xcodebuild build`, `xcodebuild test`
- AI enhance UI works unchanged from user perspective
- **UI smoke**: source chip shows **AI / 规则 / Legacy** correctly per
  current value (Manual case is unit-tested; not visible in UI in P1
  since no edit UI exists)
- Legacy session shows "Pre-v0.2.9 baseline" badge
- After regenerate, legacy badge replaced with current AI source chip
- `understanding.json` continues to receive V1 writes (dual-write);
  `understanding-v2.json` created and contains regenerate output
- Smoke test on shipped Release build confirms AI / 规则 / Legacy chip
  behavior

---

## Branch and PR

- Branch: `feature/v0.2.9-p1-data-model`
- PR: opens after C1-C6 complete with full verification per commit
- Target: `main`
- Merge style: merge commit (no squash, no rebase)
