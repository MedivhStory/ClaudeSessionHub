# Verification Handoff: Phase 12 — Final release gate (pre-tag)

**Branch:** feature/v0.2.8-ai-eval
**Commit SHA:** cc4a2cec899586db4c0386f410cda608aac8816c
**Handoff time:** 2026-04-13T14:35:01Z
**Phase:** 12 — End-to-end release gate (🛑 FINAL verify checkpoint; pre-tag)

## 1a. What changed

### Affected components (since Phase 10 checkpoint)

- `Sources/ClaudeSessionHub/Services/LLMPrompts.swift` (modified across 3 commits):
  - `ae90153` — `versionClauseShared` summary-side strengthened (fixes synthetic-version-hallucination-01 v0.2.0 leak)
  - `9d9bde6` — `baseTitleSystemPrompt` anti-recency language strengthened (fixes real-snapshot-02 title tail-drift)
  - `5ac5efb` — hard-cap length wording + title compression good/bad example pair (stabilizes length variance; ≥3/3 clean dev-mode runs achieved)
- `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json` (new — committed at `cc4a2ce`):
  - First v0.2.8 release-mode eval artifact
  - mode=release, gateResult=PASS, 6/6 fixtures passed

(Plus all Phase 1–10 components from previous checkpoints)

### Spec references

- Implements end-to-end: §2.5 (release artifact schema), §6.1 (gate-runs directory), I-2 (two-layer verification), I-3 (canonical provider locked), I-4 (8-way binding), I-5 (promptBuilderHash definition), I-14 (version clause zero-detection), I-15 (release gate mechanical + process rule)
- Applies fail-closed semantics: gateResult must be PASS, no "ship with N/M" waiver, no silent known-limitation annotations

### Change description

- **Prompt fix #1 (summary version leak)**: `versionClauseShared` third bullet elevated from "禁止" to "绝对禁止" with summary-specific callout and concrete wrong/right example for "向后兼容适配". This fixed the synthetic-version-hallucination-01 summary.mustNotContain("v0.2.0") failure.
- **Prompt fix #2 (title tail-bias)**: `baseTitleSystemPrompt` anti-recency bullets elevated to **必须** wording; added explicit priority rule [首条]/[版本锚点] > [末条]; added concrete negative example matching the real-snapshot-02 failure (v0.2.x session wrongly titled as Xcode CI update); added quantitative long-session threshold (>100 entries/turns). This fixed the real-snapshot-02 title.mustContainAny failure.
- **Prompt fix #3 (length variance stabilization)**: Soft `最多 N 个字` replaced with hard-cap `严格不超过 N 个字（含标点）；超出删减后再返回` for both title (30) and summary (150) prompts. Added title compression discipline bullet with concrete good/bad example pair. This reduced qwen-plus output length variance and converted a 1/3 flake rate (runs 1 and 2 each had a different length failure) to 3/3 consecutive clean dev-mode runs. No fixture constraints changed; no numeric prompt limits changed; no architectural changes.
- **Release-mode run**: single execution of `swift run eval-harness live --release --tag v0.2.8 --fixtures Tests/Fixtures/eval` on candidate commit `5ac5efb`. Result: 6/6 PASS, gateResult=PASS. No retry pattern used ("ε / rerun-until-green" explicitly rejected by user protocol).
- **Artifact committed**: `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json` committed at `cc4a2ce` and pushed to origin. After commit, HEAD = artifact commit (`cc4a2ce`), HEAD^ = candidate commit (`5ac5efb`) — satisfying I-15 "commit artifact before check-artifact" step.
- **check-artifact passed**: all 8-way binding checks in I-4 pass on the current branch state (mode/commitSHA/promptBuilderHash/dslSchemaVersion/provider/model/temperature/gateResult).

### Scenarios

- `docs/verify/scenarios/004-sampling-library-complete.md` (Phase 4 checkpoint, previously verified)
- `docs/verify/scenarios/007-build-plugin-hasher.md` (Phase 7 checkpoint, previously verified)
- `docs/verify/scenarios/010-fixture-set.md` (Phase 10 checkpoint, previously verified)
- `docs/verify/scenarios/012-release-gate.md` (this checkpoint — new)

## 1b. Environment requirements

### LLM mode

- **`real`** — the `live --release` run already completed and its artifact is committed. No further LLM invocations are required for the verify team to validate this checkpoint. All steps in `docs/verify/scenarios/012-release-gate.md` are read-only (inspect committed artifact + run check-artifact which does NOT call LLM + run swift test).

### Required environment variables

- none for the verification scenario steps
- (DashScope key was required at release-mode run time and resolved via `~/.claude-hub/.apiKey.secret`; verifier does not need it)

### Network

- `offline OK` — all verification steps are local file reads + local Swift test execution + local `check-artifact` (no network calls)

### Xcode version

- Xcode 26.4 or newer (v0.2.8 baseline)

### MCP availability assumptions

- none beyond baseline (macos-automator + playwright user-scope available but unused at this checkpoint)

### Pre-flight installs

- none

### macOS permission requirements

- none beyond macos-automator baseline

## Notes for verifier

### Critical invariants to spot-check

1. **Artifact content equals current branch state**: the artifact's `promptBuilderHash` must match what `swift run eval-harness check-artifact --tag v0.2.8` computes from current `LLMPrompts.swift`. If the prompt file was modified after release-mode run but before verification, `check-artifact` will reject. Any such divergence is a blocker.
2. **commitSHA = HEAD^**: the artifact's `commitSHA` field must equal `git rev-parse HEAD^` on the current branch. If you pull fresh commits on top, HEAD^ changes, and check-artifact will reject.
3. **Canonical provider locked**: artifact's provider/model/temperature must equal `CanonicalGate` constants (dashscope / qwen-plus / 0). Environment variable overrides are impossible in release mode (LiveRunConfig rejects them with a warning). Verify.
4. **Fail-closed semantics**: any fixture FAIL in artifact.fixtureResults = release blocked. The artifact shows 6/6 PASS — verify this directly.

### The 3 known LLM quality fixes that landed this round

1. synthetic-version-hallucination-01 summary leak — FIXED (not silently waived)
2. real-snapshot-02 title tail-drift — FIXED (not silently waived)
3. Length variance causing 1/3 flake — FIXED by hard-cap wording (not by loosening fixtures)

None of these were resolved by weakening fixture constraints, spec changes, or "known-limitation" annotations. All were prompt-side fixes that preserved the fail-closed gate semantics.

### Release-mode run was SINGLE, not retry-until-green

The release-mode run was executed ONCE and passed on first attempt. The 3 consecutive clean dev-mode runs prior to release-mode run were reliability evidence, not retries of the release-mode run itself. This distinction matters: the user's protocol rejected pattern ε ("rerun until green in release mode") as ethically dubious under fail-closed semantics.

### Full commit range for Phase 11 + Phase 12 (since Phase 10 checkpoint)

```
2af4299 docs(eval): v0.2.8 harness documentation (Phase 11)
c90f64d chore(gitignore): dist/eval-artifacts/dev/ (Phase 11)
ae90153 fix(prompts): strengthen versionClauseShared summary-side
9d9bde6 fix(prompts): strengthen title anti-recency language
5ac5efb fix(prompts): hard-cap length wording + title compression example pair
cc4a2ce chore(eval): v0.2.8 release gate artifact
```

### Out of scope for this verification

- **Tag creation**: explicitly reserved for user approval after this verify checkpoint passes
- **Phase 10 checkpoint**: already approved in a previous verify round
- **Phase 4 / Phase 7 checkpoints**: already approved in previous verify rounds
- **Further prompt iteration**: the current prompts are what the release gate validates against; changes would invalidate the artifact

## Commit state at handoff time

- HEAD: `cc4a2cec899586db4c0386f410cda608aac8816c` (artifact commit)
- HEAD^: `5ac5efb37656812985c2ac3c7fed61e3286295df` (candidate commit)
- Branch: `feature/v0.2.8-ai-eval`
- Pushed to origin: yes
- Remote state: `origin/feature/v0.2.8-ai-eval` == `HEAD` == `cc4a2ce`
