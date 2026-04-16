# Verify Decision: Phase 12 RERUN — Final Release Gate (post xcodeproj fix)

**Round ID:** 2026-04-14-phase12-rerun-after-xcodeproj-fix
**Scenario:** `docs/verify/scenarios/012-release-gate.md` (updated 2026-04-14 for rerun)
**Handoff manifest:** `docs/verify/handoff-manifest.md` (handoff time 2026-04-14T13:03:34Z)
**Audit performed:** 2026-04-14
**Branch:** `feature/v0.2.8-ai-eval`
**Branch tip at audit time:** `fabfaf17f67707ee3aa81d53353c2091fc8d7547`
**Proposed tag target (NEW):** `57cd04f6563404d9b0d82d998ed002575ddfaad5` — 2026-04-14 release gate rerun artifact commit
**Candidate commit (NEW, parent of tag target):** `490fa72e0f628f254c4bb6a3225b731074507c46` — xcodeproj fix
**Old tag target (retained as audit history, NOT release decision):** `cc4a2cec899586db4c0386f410cda608aac8816c`
**Authoritative release artifact:** `docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json`

---

## Decision

**ACCEPT** — Phase 12 RERUN release gate audit passes on the post-xcodeproj-fix state. Cleared for `v0.2.8` tag creation (or re-pointing) onto commit `57cd04f` pending explicit user approval.

This audit is read-only. No source, fixture, spec, plan, or artifact files were modified. No `eval-harness live` rerun was invoked. No git tag was created or rewritten. The working tree and git HEAD were restored to handoff state after the `check-artifact` step. The old `2026-04-13` artifact was preserved intact side-by-side with the new `2026-04-14` artifact as audit history.

---

## Step-by-step results (scenario 012 rerun, 9 steps)

| Step | Check | Expected | Actual | Result |
|------|-------|----------|--------|--------|
| 1 | Both artifacts present side-by-side | two `.json` files in `docs/eval/gate-runs/` | `2026-04-13-v0.2.8-5ac5efb3.json` (4270 B, Apr 13) + `2026-04-14-v0.2.8-490fa72e.json` (4239 B, Apr 14) | **PASS** |
| 2 | New artifact critical fields (9) | all 9 match scenario expected | all 9 match exactly | **PASS** |
| 3 | New artifact fixtureResults | 6 PASS / 0 FAIL | 6 PASS / 0 FAIL | **PASS** |
| 4 | `check-artifact --tag v0.2.8` at `57cd04f` | `✓ Gate check passed`, commitSHA `490fa72…`, provider `dashscope/qwen-plus`, PASS | exact match (see verbatim below) | **PASS** |
| 5 | `git rev-parse 57cd04f^` | `490fa72e0f628f254c4bb6a3225b731074507c46` | `490fa72e0f628f254c4bb6a3225b731074507c46` | **PASS** |
| 6 | Old artifact preserved intact | commitSHA `5ac5efb…`, gateResult PASS, promptBuilderHash identical to new | exact match (see below) | **PASS** |
| 7 | PR #17 CI green on a commit containing xcodeproj fix | SPM + Xcode jobs pass on a ≥`490fa72` commit | Both pass on `fabfaf17` (ancestor-verified to contain `490fa72`) | **PASS** |
| 8 | `swift test` (SwiftPM) | 339 / 0 failures | `Executed 339 tests, with 0 failures (0 unexpected) in 0.421 (0.434) seconds` | **PASS** |
| 9 | `xcodebuild test` `ClaudeSessionHubTests` | `** TEST SUCCEEDED **`, 155 tests | `Executed 155 tests, with 0 failures … ** TEST SUCCEEDED **` | **PASS** |

**Verdict: 9/9 scenario steps PASS.**

---

## Step 2 — full field values observed (NEW artifact)

| Field | Expected | Observed |
|---|---|---|
| `mode` | `release` | `release` |
| `tagLabel` | `v0.2.8` | `v0.2.8` |
| `commitSHA` | `490fa72e0f628f254c4bb6a3225b731074507c46` | `490fa72e0f628f254c4bb6a3225b731074507c46` |
| `gateResult` | `PASS` | `PASS` |
| `provider` | `dashscope` | `dashscope` |
| `model` | `qwen-plus` | `qwen-plus` |
| `temperature` | `0` | `0` |
| `dslSchemaVersion` | `1` | `1` |
| `promptBuilderHash` | `sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a…` | `sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a7b5f65f1294db34b000cb384` |

All 9 fields match the scenario's expected values exactly.

## Step 3 — fixtureResults (NEW artifact)

```
PASS: real-snapshot-01
PASS: real-snapshot-02
PASS: synthetic-cross-version-range-01
PASS: synthetic-empty-progress-01
PASS: synthetic-tail-bias-01
PASS: synthetic-version-hallucination-01
```

6 PASS / 0 FAIL. Fail-closed semantics satisfied — no waiver, no "ship with N/M" annotation, no fixture-constraint loosening.

## Step 4 — `check-artifact` output (HEAD detached at `57cd04f`)

Pre-detach tree state (`git status --porcelain`):
```
?? docs/verify/runs/2026-04-14-phase12-release-gate/
```
Only the stale dir from the pre-rerun round, explicitly left untracked by the handoff. No modifications present.

Detach: `HEAD → 57cd04f6563404d9b0d82d998ed002575ddfaad5`.

`swift run eval-harness check-artifact --tag v0.2.8` tail output:
```
✓ Gate check passed for tag 'v0.2.8'
  commitSHA: 490fa72e0f628f254c4bb6a3225b731074507c46
  promptBuilderHash: sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a7b5f65f1294db34b000cb384
  provider: dashscope / qwen-plus
  gateResult: PASS
```

**Strict unique-match discrimination verified:** with two v0.2.8-tagged artifacts now in `docs/eval/gate-runs/`, `check-artifact` at detached HEAD `57cd04f` picked the **NEW** artifact (commitSHA `490fa72…`), not the OLD one (`5ac5efb…`). The filter correctly uses the `commitSHA == git rev-parse HEAD^` triple discriminator to isolate the post-fix artifact. Running at the branch tip `fabfaf17` would have produced a false FAIL because `fabfaf17^` = `3a00236`, not `490fa72`.

Post-step restore: `HEAD → fabfaf17f67707ee3aa81d53353c2091fc8d7547`, `git status --porcelain` shows only the same benign untracked dir. Clean.

## Step 5

`git rev-parse 57cd04f^` → `490fa72e0f628f254c4bb6a3225b731074507c46` ✓ (equals the NEW artifact's `commitSHA` field; works from any branch state).

## Step 6 — old artifact preserved

```
commitSHA: 5ac5efb37656812985c2ac3c7fed61e3286295df
gateResult: PASS
promptBuilderHash: sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a7b5f65f1294db34b000cb384
```

**The promptBuilderHash is byte-identical between the 2026-04-13 and 2026-04-14 artifacts.** This confirms the xcodeproj fix did not touch any LLMPrompts source or system-prompt content — the two artifacts differ only by commitSHA (semantic prompt state unchanged). I-5 promptBuilderHash stability across the fix is verified.

## Step 7 — PR #17 CI

`gh pr checks 17 --repo MedivhStory/ClaudeSessionHub`:

| Check | Status | Duration | Run / Job |
|---|---|---|---|
| SPM Unit Tests | **pass** | 1m2s | run `24401157691` job `71271830283` |
| Xcode Unit + UI Tests | **pass** | 3m56s | run `24401157691` job `71271830298` |

**Note:** the manifest cited run `24399202510` on commit `490fa72`; `gh pr checks` surfaces the more recent run `24401157691` instead. Ancestor check performed:

- `gh run view 24401157691 --json headSha` → `headSha: fabfaf17f67707ee3aa81d53353c2091fc8d7547`
- `git merge-base --is-ancestor 490fa72 fabfaf17` → exit 0 (ancestor)
- Commits between `490fa72..fabfaf17`: `57cd04f` (rerun artifact), `3a00236` (rerun handoff), `fabfaf1` (ship plan). All docs/artifact commits; no source/project-file changes.

Therefore the green CI at `fabfaf17` validates a working tree containing the xcodeproj fix plus three pure-docs commits on top. Dual-build validation (SwiftPM + Xcode) is trustworthy and covers the post-fix state. The manifest's cited `24399202510` run ID is a documentation detail, not a substantive audit concern; recommend a minor doc fix to update the manifest to `24401157691` but this does not affect the verdict.

## Step 8 — SwiftPM tests

```
Executed 339 tests, with 0 failures (0 unexpected) in 0.421 (0.434) seconds
```
339 / 0 — matches Phase 10 baseline. Unchanged by the xcodeproj fix (project.pbxproj is data only; SwiftPM never read it).

## Step 9 — Xcode tests

```
Test Suite 'ClaudeSessionHubTests.xctest' passed at 2026-04-14 09:23:03.560.
  Executed 155 tests, with 0 failures (0 unexpected) in 0.329 (0.386) seconds
Test Suite 'All tests' passed at 2026-04-14 09:23:03.560.
  Executed 155 tests, with 0 failures (0 unexpected) in 0.329 (0.387) seconds
** TEST SUCCEEDED **
```

**This is the load-bearing evidence for the rerun.** Under the 2026-04-13 candidate state (pre-fix), `xcodebuild test` on `ClaudeSessionHubTests` would have failed with "cannot find type" errors because the 4 Phase 1-3 production files and 4 corresponding test files were missing from `project.pbxproj`. Under the 2026-04-14 candidate state (post-fix), all 155 Xcode-target tests build and pass. The `490fa72` fix delivered what the release gate tool could not verify on its own: **dual-build system consistency**.

---

## Invariants spot-checked (manifest §"Critical invariants")

| # | Invariant | Status |
|---|---|---|
| 1 | NEW artifact `commitSHA` == parent of tag target `57cd04f` | **PASS** — `git rev-parse 57cd04f^` = `490fa72…` = artifact `commitSHA` |
| 2 | Old artifact preserved side-by-side, unmodified | **PASS** — `2026-04-13-v0.2.8-5ac5efb3.json` intact, commitSHA `5ac5efb…`, gateResult PASS |
| 3 | PR #17 CI green on a commit containing the xcodeproj fix | **PASS** — SPM + Xcode jobs green on `fabfaf17`, ancestor-verified to contain `490fa72` |
| 4 | Strict unique match still works with two v0.2.8 artifacts | **PASS** — `check-artifact` at `57cd04f` picked NEW (`490fa72…`), not OLD (`5ac5efb…`) |
| 5 | `promptBuilderHash` unchanged between 2026-04-13 and 2026-04-14 | **PASS** — both = `sha256:6e095c7101…cb384`, confirming xcodeproj fix touched no prompt source |

**8-way binding (I-4):** mode / commitSHA / promptBuilderHash / dslSchemaVersion / provider / model / temperature / gateResult — all 8 verified consistent between the committed 2026-04-14 artifact JSON and the live `check-artifact` recomputation at `57cd04f`.

## Process invariants

- **Single release run, first-attempt PASS** — manifest documents the 2026-04-14 release-mode run was a single execution. Only one 2026-04-14 artifact file exists in `docs/eval/gate-runs/` (dated 2026-04-14, commitSHA `490fa72…`), consistent with no retry-until-green pattern.
- **No silent waivers** — 6/6 PASS on identical fixtures as the 2026-04-13 run; no fixture-constraint changes, no spec changes, no "known-limitation" annotations.
- **Old chain preserved** — fail-closed audit philosophy satisfied: the 2026-04-13 gate-run PASS record is retained as evidence of "what ran on the pre-fix state," not erased.

---

## Constraints honored during this audit

- No `eval-harness live --release` rerun — existing authoritative artifact not duplicated
- No `eval-harness live --dev` rerun
- Neither artifact file modified (`docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json` and `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json` both intact)
- No git tag created or rewritten — retag decision reserved for user approval
- PR #17 not merged
- No source / fixture / spec / plan / `project.pbxproj` modified
- Working tree clean-except-benign-untracked before HEAD detach; restored to `feature/v0.2.8-ai-eval` @ `fabfaf17…` after `check-artifact`; `git status --porcelain` post-restore shows only the expected `?? docs/verify/runs/2026-04-14-phase12-release-gate/`
- Accept-decision written under the FRESH rerun dir `docs/verify/runs/2026-04-14-phase12-rerun-after-xcodeproj-fix/`, NOT the stale pre-rerun dir

---

## Minor doc follow-up suggested (not required)

Handoff manifest §"Notes for verifier" item 3 cites PR #17 CI run `24399202510` on commit `490fa72`. The currently-surfaced green run is `24401157691` on commit `fabfaf17` (which contains `490fa72` as an ancestor). Manifest could be updated to cite `24401157691` / `fabfaf17` for accuracy. This is a pure documentation delta and does not affect the audit verdict.

---

## Recommendation

**Proceed with `v0.2.8` tag (re-)creation on commit `57cd04f6563404d9b0d82d998ed002575ddfaad5`** when the user gives explicit approval.

The current `v0.2.8` tag points at the old `cc4a2ce` artifact commit (the pre-fix state that did not build under Xcode). Re-pointing the tag to `57cd04f` will carry the release decision onto the post-xcodeproj-fix state whose dual-build (SwiftPM + Xcode) consistency is now verified.

Re-tag command (for user reference, NOT executed by this audit):

```bash
git tag -f v0.2.8 57cd04f -m "v0.2.8 — AI evaluation harness release (post xcodeproj fix)"
git push -f origin v0.2.8
```

The `-f` flag is required because a tag already exists at `cc4a2ce`. Tag force-push is an explicit user decision; this audit only validates that the destination commit `57cd04f` is eligible.

No further verification work is required from this team. All four checkpoints (Phase 4, Phase 7, Phase 10, and Phase 12 rerun) have now passed on their respective candidate states.

---

## Audit team

- **Team:** `cshub-verify`
- **Lead:** team-lead (this report author)
- **artifact-auditor** — task #1 (steps 1, 2, 3, 5, 6, 7 + follow-up CI ancestry check)
- **harness-runner** — task #2 (steps 4, 8, 9)

Both teammates executed read-only and will be shut down cleanly after this report is written.
