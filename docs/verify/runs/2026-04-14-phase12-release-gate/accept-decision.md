# Verify Decision: Phase 12 — Final Release Gate (pre-tag)

**Round ID:** 2026-04-14-phase12-release-gate
**Scenario:** `docs/verify/scenarios/012-release-gate.md`
**Handoff manifest:** `docs/verify/handoff-manifest.md` (handoff time 2026-04-13T14:35:01Z)
**Audit performed:** 2026-04-14
**Branch:** `feature/v0.2.8-ai-eval`
**Branch tip at audit time:** `b33d9d0167245339d1ce0d2e19036e749a411efd`
**Tag target commit:** `cc4a2cec899586db4c0386f410cda608aac8816c` (artifact commit)
**Candidate commit:** `5ac5efb37656812985c2ac3c7fed61e3286295df` (parent of tag target)

---

## Decision

**ACCEPT** — Phase 12 release gate audit passes. Cleared for `v0.2.8` tag creation pending explicit user approval.

This audit is read-only. No source, fixture, spec, plan, or artifact files were modified. No `eval-harness live` run was invoked. No git tag was created. The working tree and git HEAD were restored to the handoff state after every step.

---

## Step-by-step results (scenario 012)

| Step | Check | Expected | Actual | Result |
|------|-------|----------|--------|--------|
| 1 | Artifact file exists and was committed at `cc4a2ce` | file present, introduced by `cc4a2ce` | 4270 bytes; introducing commit `cc4a2ce chore(eval): v0.2.8 release gate artifact` | **PASS** |
| 2 | 9 critical artifact fields | see below | all 9 match exactly | **PASS** |
| 3 | All 6 fixtures passed in artifact | 6 PASS / 0 FAIL | 6 PASS / 0 FAIL | **PASS** |
| 4 | `check-artifact --tag v0.2.8` with HEAD detached at `cc4a2ce` | `✓ Gate check passed`, expected fields echoed | `✓ Gate check passed for tag 'v0.2.8'`, all fields echoed correctly | **PASS** |
| 5 | `git rev-parse cc4a2ce^` | `5ac5efb37656812985c2ac3c7fed61e3286295df` | `5ac5efb37656812985c2ac3c7fed61e3286295df` | **PASS** |
| 6 | Full unit test suite | 339 / 0 failures | 339 / 0 failures | **PASS** |

**Verdict: 6/6 scenario steps PASS.**

---

## Step 2 — full field values observed

| Field | Expected | Observed |
|---|---|---|
| `mode` | `release` | `release` |
| `tagLabel` | `v0.2.8` | `v0.2.8` |
| `commitSHA` | `5ac5efb37656812985c2ac3c7fed61e3286295df` | `5ac5efb37656812985c2ac3c7fed61e3286295df` |
| `gateResult` | `PASS` | `PASS` |
| `provider` | `dashscope` | `dashscope` |
| `model` | `qwen-plus` | `qwen-plus` |
| `temperature` | `0` | `0` |
| `dslSchemaVersion` | `1` | `1` |
| `promptBuilderHash` | `sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a…` | `sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a7b5f65f1294db34b000cb384` |

All 9 fields match the scenario's expected values exactly.

## Step 3 — fixtureResults

```
PASS: real-snapshot-01
PASS: real-snapshot-02
PASS: synthetic-cross-version-range-01
PASS: synthetic-empty-progress-01
PASS: synthetic-tail-bias-01
PASS: synthetic-version-hallucination-01
```

6 PASS / 0 FAIL. Fail-closed semantics satisfied — no waiver, no "ship with N/M" annotation.

## Step 4 — `check-artifact` full output (HEAD detached at `cc4a2ce`)

```
[0/3] Write swift-version--58304C5D6DBC2206.txt
warning: 'claudesessionhub_v0.2.8': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /Users/.../Sources/ClaudeSessionHub/Assets.xcassets
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build of product 'eval-harness' complete! (0.23s)
✓ Gate check passed for tag 'v0.2.8'
  commitSHA: 5ac5efb37656812985c2ac3c7fed61e3286295df
  promptBuilderHash: sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a7b5f65f1294db34b000cb384
  provider: dashscope / qwen-plus
  gateResult: PASS
```

The Assets.xcassets warning is a pre-existing cosmetic SwiftPM resource declaration warning, unrelated to the gate; observed in earlier checkpoints as well.

The HEAD-detach gotcha worked exactly as documented in the scenario notes: `check-artifact` internally does `git rev-parse HEAD^`, which only resolves to `5ac5efb` when HEAD is positioned at `cc4a2ce`. Running it from the branch tip `b33d9d0` would have produced a false FAIL because `b33d9d0^` is `072a363`, not `5ac5efb`.

## Steps 5 & 6

- `git rev-parse cc4a2ce^` → `5ac5efb37656812985c2ac3c7fed61e3286295df` ✓ (works from any branch state, no checkout needed)
- `swift test` → `Executed 339 tests, with 0 failures (0 unexpected) in 0.408 (0.419) seconds` — matches Phase 10 baseline (339/0), unchanged by the 3 prompt-fix commits between Phase 10 and Phase 12.

---

## Invariants spot-checked (manifest §"Critical invariants")

| # | Invariant | Status |
|---|---|---|
| 1 | Artifact `promptBuilderHash` matches current `LLMPrompts.swift` | **PASS** — `check-artifact` recomputed and matched (would have rejected on divergence) |
| 2 | `commitSHA` field == parent of tag target | **PASS** — `git rev-parse cc4a2ce^` = `5ac5efb…` = artifact `commitSHA` |
| 3 | Canonical provider locked (`dashscope` / `qwen-plus` / `0`) | **PASS** — all three echoed by `check-artifact` and present in artifact JSON |
| 4 | Fail-closed semantics (any FAIL = blocked) | **PASS** — 6/6 PASS, no waivers, no annotations |

**8-way binding (I-4):** mode / commitSHA / promptBuilderHash / dslSchemaVersion / provider / model / temperature / gateResult — all 8 dimensions verified consistent between the committed artifact JSON and the live `check-artifact` recomputation.

## Process invariants

- **Single release run, not "rerun until green"** — manifest documents the release-mode run was a single execution on first attempt; the 3 clean dev-mode runs preceding it were reliability evidence, not retries. Scenario 012 does not exercise this directly but the manifest claim is internally consistent (only one artifact file exists in `docs/eval/gate-runs/`, dated 2026-04-13, commitSHA `5ac5efb`).
- **No silent waivers for the 3 known LLM quality issues** — manifest documents prompt-side fixes (`ae90153`, `9d9bde6`, `5ac5efb`) for synthetic-version-hallucination summary leak, real-snapshot-02 title tail-drift, and length variance; fixture constraints unchanged. The artifact's 6/6 PASS reflects these prompt fixes, not weakened acceptance criteria.

---

## Constraints honored during this audit

- ✅ No `eval-harness live --release` rerun (avoided polluting the audit chain with a duplicate artifact)
- ✅ No `eval-harness live --dev` rerun
- ✅ Existing artifact at `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json` not modified
- ✅ No `v0.2.8` git tag created (explicitly reserved for user approval)
- ✅ No source / fixture / spec / plan modified
- ✅ Working tree clean before HEAD detach; restored to `feature/v0.2.8-ai-eval` @ `b33d9d0` after `check-artifact`; `git status --porcelain` empty post-restore

---

## Recommendation

**Proceed with `v0.2.8` tag creation on commit `cc4a2cec899586db4c0386f410cda608aac8816c`** when the user gives explicit approval.

Tag command (for user reference, NOT executed by this audit):

```bash
git tag -a v0.2.8 cc4a2ce -m "v0.2.8 — AI evaluation harness release"
git push origin v0.2.8
```

No further verification work is required from this team. All four checkpoints (Phase 4, Phase 7, Phase 10, Phase 12) have now passed.

---

## Audit team

- **Team:** `cshub-verify`
- **Lead:** team-lead (this report author)
- **artifact-auditor** — task #1 (steps 1, 2, 3, 5)
- **harness-runner** — task #2 (steps 4, 6)

Both teammates executed read-only and shut down cleanly after reporting.
