# PLAN-v0.2.9 — AI Understanding Layer Refactor

**Created**: 2026-04-27
**Status**: Planning (no implementation yet)
**Predecessor**: v0.2.8.3 (`792dfd8`)
**Doc type**: State doc — update in place during planning

---

## 1. Version charter and user promise

### Charter

AI understanding layer refactor. Title, progress, and summary become
traceable, expirable, correctable, recall-supportive current
interpretations of a session.

### Promise to user

> 用户打开 AI 理解面板时,能清楚知道当前标题、进展、摘要是什么,
> 它们从哪里来,是否过期,为什么可信,能不能修正。

### Version principles

- Not a prompt-tuning release.
- Not an automation release.
- Manual generation drives v0.2.9; auto-trigger deferred.
- Source, staleness, and provenance must be visible for every current value.

### Success criteria

1. User can tell whether title / progress / summary comes from AI, rule,
   or manual edit.
2. User can tell whether the current understanding is stale relative to
   session content.
3. User can recall what a session was about by looking at evidence below
   the AI panel.
4. User can correct title and progress without being silently overwritten
   by AI.
5. Summary regenerate uses current title, progress, and evidence as inputs.
6. Long sessions show measurable reduction in wrong-topic capture, missing
   current phase, and phantom completion claims (advisory regression set).

---

## 2. Current problems being solved

- Sessions whose first user text starts with verbs outside the rule pattern
  fall through to UUID fallback titles. v0.2.8.3 partially addressed this
  with verb-pattern expansion; the underlying 10+50 window limitation remains.
- AI generates wrong titles for long multi-topic sessions; users have no way
  to correct without losing the AI semantic layer.
- AI hallucinates version numbers and capabilities (#7 prompt scope-creep
  clauses reverted in v0.2.8.1, never re-evaluated).
- No staleness signal — users cannot tell if AI understanding matches current
  session state.
- No source attribution — users cannot tell whether title came from rule,
  AI, or their own edit.
- AI re-generation silently overwrites prior values with no version trail.
- No evidence to support recall — users see AI output without underlying
  signals.
- Synthetic fixtures don't catch real-session quality regressions
  (release-gate blind spot, addressed advisory-only in v0.2.9).

---

## 3. Explicit non-scope

- Auto-triggered AI generation
- Silent background refresh of AI understanding
- User-editable summary text
- Full desensitization UX (CLI-only minimum stays in scope)
- Multi-candidate voting / suggestion override
- Real samples in release gate (advisory only)
- Resume time-anchor calibration
- Agent spawn model flag inheritance
- Dual-build CI / membership linter
- Large-scale eval infrastructure refactor
- Rule engine full-scan rewrite for `extractSignals`
  (deeper #5 fix; only `extractEnhanceInputs` is touched)

### Deferred targets

- v0.2.9.1: auto-trigger strategy, token / cost controls, complex override
  conflict.
- v0.2.9.2 or later: real-sample release-gate integration, fixture shape
  cleanup, dual-build linter, membership linter.

---

## 4. Data model proposal

### Storage files

- `~/.claude-hub/understanding.json` (legacy): **read-only**. Never mutated,
  never renamed by v0.2.9. Continues to exist as the source of legacy
  snapshots.
- `~/.claude-hub/understanding-v2.json` (new): all v0.2.9 versioned artifacts,
  current pointers, and selection events.

### Core types (Swift, sketch)

```swift
public enum UnderstandingSource {
    case rule
    case ai
    case manual
}

public enum UnderstandingTrigger {
    case scan           // produced during normal scan (rule layer)
    case manualGenerate // user clicked regenerate
    case manualEdit     // user typed
}

public enum StaleState {
    case fresh
    case staleSessionUpdated(at: Date)
    case stalePartial(reason: String) // depends on an edited field
    case legacyUnknown                 // pre-v0.2.9 baseline; no precise staleness
}

public struct UnderstandingArtifact {
    let id: UUID
    let value: String
    let source: UnderstandingSource
    let trigger: UnderstandingTrigger
    let createdAt: Date
    let sessionFingerprint: String   // hash of session state at generation
    let inputEvidenceRef: String?    // reference to evidence snapshot if any
    let staleState: StaleState
    let promptVersion: String?       // for AI artifacts
    let modelName: String?           // for AI artifacts
}

public enum UnderstandingField {
    case title
    case progress
    case summary
}

public enum SelectionAction {
    case adopt
}

public struct SelectionEvent {
    let id: UUID
    let field: UnderstandingField
    let action: SelectionAction
    let targetVersionID: UUID
    let timestamp: Date
}

public struct RationaleMetadata {
    let text: String
    let trigger: UnderstandingTrigger
    let createdAt: Date
    let basedOnTitleVersionID: UUID?
    let basedOnProgressVersionID: UUID?
    let basedOnSummaryVersionID: UUID?
    let evidenceRefs: [String]
    let staleState: StaleState
}

public struct LegacyUnderstandingSnapshot {
    let title: String?
    let progress: String?
    let summary: String?
    let generatedAt: Date
    let modelName: String?
}

public struct UnderstandingState {
    let sessionID: String
    var titleVersions: [UnderstandingArtifact]
    var currentTitleVersionID: UUID?       // explicit current pointer
    var progressVersions: [UnderstandingArtifact]
    var currentProgressVersionID: UUID?
    var summaryVersions: [UnderstandingArtifact]
    var currentSummaryVersionID: UUID?
    var selectionEvents: [SelectionEvent]  // adoption history
    var currentRationale: RationaleMetadata?
    var legacySnapshot: LegacyUnderstandingSnapshot?
}
```

### Pointer semantics

Each field has an optional `currentXVersionID` pointer:

- When the pointer is set, display uses that exact artifact.
- When the pointer is nil, display falls back to precedence policy
  (Section 6).
- Edit (`source = .manual`) creates a new artifact AND sets the pointer
  to it.
- AI regenerate (`source = .ai`) creates a new artifact:
  - If the current pointer is nil or points to an AI artifact, the pointer
    moves to the new AI artifact.
  - If the current pointer points to a manual artifact, the pointer does
    NOT move. The new AI artifact is appended to the chain as a candidate.
- "Adopt AI version" sets the pointer to a specific AI artifact and
  appends a `SelectionEvent`. **No new artifact is created.** The AI
  artifact retains `source = .ai`.

---

## 5. Hybrid migration strategy

On first launch of v0.2.9:

1. If `understanding.json` exists, leave it untouched. Read it as
   read-only legacy input.
2. If `understanding-v2.json` does not exist, create it empty.
3. Per session, derive `legacySnapshot` from the legacy file at read time
   (not migrated, not mutated).
4. If no v2 versions exist for a session, the legacy snapshot may serve
   as a display candidate, marked "Pre-v0.2.9 baseline".
5. Legacy retention is permanent. Even after the first regenerate creates
   a v2 chain, the legacy snapshot remains accessible in the history drawer.
6. Legacy fields are all optional (`title?`, `progress?`, `summary?`).
   Missing fields fall back through the existing display policy
   (Section 6) to the rule layer.
7. Legacy snapshots are read-only. Users cannot edit or delete them.
8. Legacy artifacts are never inserted into the v2 version chain. They
   lack evidence refs, trigger metadata, prompt version, and session
   fingerprint; inserting them as v1 artifacts would manufacture false
   provenance.

---

## 6. Display policy

### Field precedence

| Field    | Precedence (top wins)                                           |
|----------|-----------------------------------------------------------------|
| Title    | Manual (v2) > AI (v2) > Legacy.title > Rule > UUID prefix       |
| Progress | Manual (v2) > AI (v2) > Legacy.progress > Rule / derived        |
| Summary  | AI (v2) > Legacy.summary > nil (no display)                     |

### Resolution algorithm (per field)

1. If `currentXVersionID` is set, display that exact v2 artifact.
2. Else, walk the precedence above, top to bottom:
   - **Manual (v2)**: latest manual artifact in the chain by `createdAt`.
   - **AI (v2)**: latest AI artifact in the chain by `createdAt`.
   - **Legacy**: corresponding optional field on `legacySnapshot`.
   - **Rule / UUID**: existing rule layer fallback.

### Rules

- Manual edit always wins over AI for title and progress, unless the user
  explicitly adopts the AI version via the pointer.
- AI re-generation creates a candidate; it does not silently demote a manual
  current pointer.
- Summary has no manual edit path. Users cannot directly write summary text.
- Legacy ranks above Rule for title and progress (it is a previously curated
  AI output, not raw structural extraction).
- Source chip and staleness marker are always visible on every current value.

---

## 7. Edit and regenerate flows

### User actions

| Action                           | Effect                                                                                                                                                                |
|----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Edit title (inline)              | New title artifact, `source = .manual`. `currentTitleVersionID` moves to it. Rationale marked `.stalePartial`.                                                        |
| Edit progress (inline)           | Same as title.                                                                                                                                                        |
| Regenerate title                 | Single LLM call. New AI artifact. Pointer moves only if previous current was nil or AI. Otherwise candidate.                                                          |
| Regenerate progress              | Same as title.                                                                                                                                                        |
| Regenerate summary               | Single LLM call. New AI artifact. Pointer moves (no manual path for summary). Optional rationale refresh (toggle, default on).                                        |
| Full regenerate AI understanding | Title + progress + summary calls. Each follows its own pointer rule. Rationale call attempted by default (failure does not block).                                    |
| Adopt AI version                 | User explicitly switches `currentXVersionID` to an existing AI artifact. **No new artifact is created.** A `SelectionEvent(action: .adopt)` is appended. The AI artifact retains `source = .ai`. |

### Constraints

- AI regenerate cannot silently override a manual current pointer.
- UI surfaces "AI version available — adopt?" when an AI candidate exists
  alongside a manual current.
- Concurrent edit during regenerate: AI result becomes a candidate; the
  user decides which version becomes current.

---

## 8. Staleness and history

### Staleness states

- `.fresh` — generated for the current session state.
- `.staleSessionUpdated(at: Date)` — session has new content after this
  artifact's `createdAt`.
- `.stalePartial(reason)` — depends on a different field that has been
  edited since this artifact was generated. Example: rationale references
  a title version that's no longer current.
- `.legacyUnknown` — pre-v0.2.9 baseline; no precise staleness available.

### UI affordances

- Source chip: "AI" / "规则" / "手动" / "Legacy".
- Stale badge with explanation: "Session updated 3 hours after this was
  generated".
- "Regenerate to refresh" CTA when stale.
- History drawer per field shows all v2 artifacts AND selection events
  in chronological order, with a "currently selected" mark on the
  artifact pointed to by `currentXVersionID`.

### History storage

- Per-field artifact chain appends **only** on regenerate or edit.
- Adopt does **not** append a new artifact; it appends a `SelectionEvent`
  and moves the current pointer.
- Legacy snapshot kept permanently (one per session).
- Rationale has no history (current-only, replaced on regen).
- History drawer renders artifact entries and selection events
  interleaved chronologically, so users see "AI generated → Manual edit →
  AI regenerated (candidate) → User adopted AI" as a timeline.

---

## 9. Evidence layer

### Purpose

Help users recall what a session was about. Provide grounding for the
optional AI rationale.

### Sources (rule / structural only)

- Recent files modified (existing `SessionDetail.recentFiles`)
- Recent tool operations (existing `SessionSignals.toolsUsed`)
- Time anchors: created, last active, milestone events
- Branch and cwd
- Related sessions (existing `SessionStore.relations`)
- Project name (existing `ProjectNameResolver`)
- Current phase (derived from task state if any, else nil)
- Latest assistant progress signal (existing `lastAssistantProgress`)

### UI

Rendered below the AI panel, expandable. Items are static text; users
cannot edit evidence.

### Hard constraint

The evidence layer **does not call the LLM**. If a category needs
interpretation, it must come from structural signals, not a separate
AI call.

---

## 10. Rationale generation and storage

### Generation

Path A — separate optional LLM call.

### Trigger rules

| Action                           | Rationale call                          |
|----------------------------------|-----------------------------------------|
| Full regenerate AI understanding | Attempted by default                    |
| Regenerate summary               | User can toggle, default on             |
| Regenerate title                 | Does not trigger                        |
| Regenerate progress              | Does not trigger                        |
| Manual edit of title or progress | Marks current rationale `.stalePartial` |

### Storage

Option 2 — current-only metadata.

- One `RationaleMetadata` per session.
- New rationale replaces old.
- Rationale history is intentionally out of scope for v0.2.9.

### Failure handling

- Rationale call failure does not fail the overall enhance operation.
- UI shows "AI rationale unavailable" or omits the rationale section.
- Evidence layer (rule-based) remains visible regardless.

### Prompt constraint

- "Explain which extracted evidence supports the current title, progress,
  and summary."
- "Do not introduce new claims not present in evidence."
- "Do not restate the summary."

---

## 11. Long-session input strategy

### Goal

Address #3 (AI quality on long multi-topic sessions). Partially addresses
#5 (deeper rule-engine window fix is non-scope).

### Approach

Extend `extractEnhanceInputs` (already does full-scan since v0.2.8.1).

### Improvements to evaluate during P5

- Topic detection: heuristic boundary signals (large time gaps, branch /
  cwd changes, task subject changes) to identify topic shifts.
- Multi-anchor sampling: for very long sessions, sample first / last K
  turns per topic cluster, not just session-wide head and tail.
- Recency weighting: tail turns slightly weighted in prompt context.
- Milestone-aware sampling: ensure existing milestone sampler is consulted
  inside `extractEnhanceInputs`, not only in rule layer.

### Boundary

This is **not** a rule-engine rewrite. The cheap `extractSignals`
head-10 / tail-50 path stays as-is. Only `extractEnhanceInputs` (the
LLM-feeding surface) gets topic-aware treatment.

---

## 12. Prompt and eval direction

### Prompt goals

- Output structure: title, progress, summary as the three core fields.
  Optional evidence rationale via a separate call (Section 10).
- Re-evaluate the v0.2.8 scope-creep clause (#7) — was reverted; with the
  new evidence layer and topic-aware input, the original protective clause
  may no longer be needed. Decide based on real-sample regression behavior.
- Explicit phantom-capability prohibition: "Do not claim files, tools, or
  completion states not present in the input."
- Summary structure: goal, completed, current phase, next or remaining.
- Multi-topic: prompt instructs "if multiple distinct topics are detected,
  summarize the main arc of the session, not every sub-task."

### Eval direction

- Synthetic fixtures retained for the release gate (existing milestone gate
  must pass before tagging — see Section 14).
- Real-sample fixtures added as advisory regression material (Section 13).
- Eval focus shifts: not "is the text well-written" but "does it catch the
  main project, current phase, real progress, with no phantom capabilities."

---

## 13. Desensitization and real-sample policy

### Tool

Extend the existing `DesensitizeSession` CLI (Path B, narrow).

### Required extensions

- Support additional mapping CSV categories: `emails.csv`,
  `project-names.csv`, `secrets.csv`, `hostnames.csv`. (Current tool
  hard-codes only `usernames.csv`, `paths.csv`, `repos.csv`.)
- Fail-closed residue scan with atomic write:
  1. Write desensitized output to a temp file.
  2. Scan output for high-risk patterns: email regex, common path roots
     (`/Users/`, `/home/`), known secret prefixes (`sk-`, `xoxb-`, etc.).
  3. If any high-risk pattern remains, refuse to move temp to requested
     output. Report which category and which sample lines failed.
  4. If clean, atomically move temp to requested output.
- Fail with a clear error if a category is uncovered (e.g., emails detected
  in raw input but `emails.csv` has no entries).

### Process rules

- Mapping CSVs kept under `/tmp/` or `~/.claude-hub/desensitize-mappings/`
  (not in repo).
- `.gitignore` entries for raw JSONL paths and mapping directories.
- Only `*.input.json` desensitized fixtures are committable to repo.

### Real-sample policy

- Fixtures stored under `Tests/Fixtures/eval/real-samples/`.
- Run manually via `eval-harness eval --fixtures real-samples`. Human reviews.
- **Not** in release gate.
- Full release-gate integration deferred to v0.2.9.2 or later.

### Initial fixture set target

- 1 long multi-topic session
- 1 sdk-cli session that originally fell through to UUID fallback
- 1 session with poor v0.2.8 AI title or summary
- 1 session with phantom-capability hallucination

---

## 14. Internal PR phasing

Single `v0.2.9` tag at the end. Multiple PRs to manage review and
rollback. Each PR runs full dual-build verification (`swift build` /
`swift test` / `xcodebuild build` / `xcodebuild test`) plus smoke test
before merge.

| PR | Scope                                                | Exit criteria                                                                                                       |
|----|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| P1 | Data model + display policy + migration              | Model migrated; legacy baseline visible; current pointer policy works; basic source chip visible. Full per-field staleness UI deferred to P3. |
| P2 | Edit + regenerate UI                                 | Title and progress editable; AI regenerate creates candidate without overwriting manual; "Adopt AI version" moves the pointer and records a selection event. |
| P3 | Staleness UI + history drawer                        | Field-level staleness explanation displayed; history drawer accessible per field showing artifacts + selection events; stale → regenerate works. |
| P4 | Evidence layer                                       | AI panel shows evidence section. Constraint: pure rule, no LLM call from this PR.                                   |
| P5 | Long-session input strategy + prompt rewrite         | `extractEnhanceInputs` topic-aware; prompts updated. Long-session fixture shows improved main-arc capture.          |
| P6 | Desensitization extension + real-sample fixtures     | `DesensitizeSession` extended with new CSV categories and fail-closed residue scan + atomic write; real-sample regression set runnable. No rationale work in this PR. |
| P7 | Rationale generation and storage                     | `RationaleMetadata` model wired; optional separate LLM call; UI integration in evidence area; failures degrade gracefully. |

### Pre-tag checklist (milestone release)

After P7 merges, before tagging `v0.2.9`:

1. Run milestone release gate:
   - `eval-harness live --release --tag v0.2.9` (produces gate artifact
     against synthetic fixtures).
   - `check-artifact --tag v0.2.9` (8-way binding validation).
   - Gate result must be `PASS`. Real-sample fixtures are advisory and
     not part of the gate.
2. Commit gate artifact on the release branch.
3. Update `CHANGELOG.md` with v0.2.9 Added / Changed / Fixed / Removed
   entries (Keep a Changelog format).
4. Open PR to `main`, CI green, merge with merge commit (no squash).
5. Tag `v0.2.9` on the merge commit. Push tag.
6. `release.yml` produces draft `.dmg` / `.zip`.
7. Manual smoke test on shipped build.
8. Publish release.
