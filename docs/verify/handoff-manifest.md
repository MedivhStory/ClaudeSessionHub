# Verification Handoff: Phase 10 — Fixture set + desensitization pilot

**Branch:** feature/v0.2.8-ai-eval
**Commit SHA:** 138c570475700796746792841ac8202c62595b29
**Handoff time:** 2026-04-13T04:08:42Z
**Phase:** 10 — Fixtures + desensitization (🛑 third verify checkpoint)

## 1a. What changed

### Affected components
- `Sources/DesensitizeSession/main.swift` (new — Task 10.2, from earlier commit 21a307f)
- `scripts/eval/precheck_desensitization.swift` (new — Task 10.3, from earlier commit d2173f3)
- `scripts/eval/README.md` (new — Task 10.3)
- `Tests/Fixtures/eval/synthetic-version-hallucination-01.{input,expected}.json` (from earlier commit)
- `Tests/Fixtures/eval/synthetic-tail-bias-01.{input,expected}.json` (from earlier commit)
- `Tests/Fixtures/eval/synthetic-empty-progress-01.{input,expected}.json` (from earlier commit)
- `Tests/Fixtures/eval/synthetic-cross-version-range-01.{input,expected}.json` (from earlier commit)
- `Tests/Fixtures/eval/real-snapshot-01.{input,expected}.json` (new — Task 10.4, commit 138c570)
- `Tests/Fixtures/eval/real-snapshot-02.{input,expected}.json` (new — Task 10.4, commit 138c570)

(Plus all Phase 1-9 components from previous checkpoints)

### Spec references
- Implements: §1.2 (6-fixture initial set), §2.1 (fixture disk layout), §2.2 (input.json schema), §2.3 (expected.json schema), §6.6 (desensitization scripts), I-6 (three-way ID consistency), I-10 (desensitization fidelity + pilot exit criteria N=2)

### Change description
- Phase 10 delivers the complete initial fixture set: **4 synthetic + 2 real-snapshot = 6 total pairs**
- DesensitizeSession executable target: package-internal tool (not a product) that reads raw Claude Code JSONL, applies mapping CSVs, emits FixtureInputFile JSON
- precheck_desensitization.swift standalone script: Foundation-only, independently maintained regex + keyword constants, produces structural fidelity report (history/user-turn count, version mentions, milestone keyword hits)
- I-10 pilot exit criteria satisfied: **N=2 real snapshots from 2 different sessions**, one mixed-context-sanity (self-referential) and one subtopic-bias+cross-version-drift
- Session-1 framing adjusted from narrow "version-hallucination+topic-drift" to broader "mixed-context-sanity" after content inspection revealed the session IS the v0.2.8 eval harness dev conversation itself (self-referential)
- 5-pattern PII verification performed on both real snapshots: all clean

### Scenarios
- `docs/verify/scenarios/004-sampling-library-complete.md` (Phase 4 checkpoint)
- `docs/verify/scenarios/007-build-plugin-hasher.md` (Phase 7 checkpoint)
- `docs/verify/scenarios/010-fixture-set.md` (this checkpoint)

## 1b. Environment requirements

### LLM mode
- `disabled` — Phase 10 is fixture authoring and validation. No LLM invocation required for the checkpoint scenarios. (The separate synthetic-only dev-mode live eval was run earlier in session 2 on commit c90f64d and is documented in the memory; it is NOT part of this checkpoint verification.)

### Required environment variables
- none for the validation steps

### Network
- `offline OK`

### Xcode version
- Xcode 26.4 or newer (v0.2.8 baseline)

### MCP availability assumptions
- none beyond baseline (macos-automator + playwright user-scope available but unused at this checkpoint)

### Pre-flight installs
- none

### macOS permission requirements
- none beyond macos-automator baseline

## Notes for verifier

### Key invariant to check: session-1 is NOT a failure-mode reproducer

Session-1 (sessionID `6a7b8e24-e480-45d2-98c8-b17d5ea11a8d`) is literally the Claude Code session in which the v0.2.8 eval harness itself was built. That is why its content naturally mixes (a) the original opening topic of agent automation UI testing research, (b) v0.2.8 spec/plan iteration, and (c) the desensitization/PII-mapping discussion that constructed the very fixture being verified. This self-referential nature means:

- `meta.failureMode` is `"mixed-context-sanity"` — NOT a drift-reproduction label
- `expected.json` deliberately uses MINIMAL constraints (non-empty + length bounds only, no mustContainAny anchor) because the session is genuinely multi-topic and any specific topic requirement would over-specify
- The fixture's purpose is **robustness-under-multi-topic-noise**, not reproducing a specific failure mode

Session-2 (sessionID `4605317d-657f-499c-8cb5-0fabe0f2875b`) is the actual failure-mode reproducer:
- `meta.failureMode` is `"subtopic-bias+cross-version-drift"`
- 990 turns, spans v0.2.5 (55) + v0.2.7 (32) + v0.2.8 (30) + v0.3.0 (14) mentions
- `expected.json` requires `"0.2"` in both title and summary (catches subtopic bias like a "DashScope integration" title that drops the version context)

### PII verification summary

5-pattern scan on both real snapshots: all zero hits for `medivh_openclaw`, `medivh-openclaw`, `/Users/medivh`, `MedivhStory`, `medivh-openclawtekiMac-mini.local`. Full sanity-check of replacements confirmed present (40+ `/Users/dev-user`, 26+ `-Users-dev-user`, 21+ `dev-machine.local`, 73+ `dev-org` in session-1).

### Mapping CSVs

Local-only at `/tmp/cshub-mapping/session-{1,2}/`. Never committed (per I-10). The minimized ruleset was approved by user and iteratively tightened over 2 rerun cycles:
- Initial (6 rules per session): base username + path + repo mappings
- +3 rules (session-1): path-encoded form, git hostname, path-scoped /Users/medivh
- +2 rules (session-1): bare medivh-openclaw handle, bare MedivhStory org name

### Full test suite state

339 tests, 0 failures. Baseline unchanged by Phase 10 (fixture files are data, not code).

### Phase 12 NOT yet run

Phase 12 full release-mode eval has NOT been executed. Only the synthetic-only dev-mode pipeline validation was run in the previous session. Full Phase 12 release gate with all 6 fixtures is still pending and is blocked on this checkpoint's approval.

### Known open issue

`synthetic-version-hallucination-01` summary still leaks `v0.2.0` in dev-mode live eval. This is a genuine LLM quality signal that the versionClauseShared prompt improvement doesn't fully eliminate. Under the locked spec's fail-closed semantics, this constitutes a release-blocking failure and cannot be silently waived. Resolution options (user decision required): (a) iterate on prompt, (b) defer release, (c) explicit spec/DSL change. Do NOT weaken the fixture constraint.

## Commit range (Phase 10 only)

```
21a307f feat(tools): DesensitizeSession executable for real-snapshot fixtures
d2173f3 feat(tools): precheck_desensitization standalone verifier + scripts README
7e41b35 fix(fixtures): tune maxLength constraints — title 30→45, summary 150→200
138c570 test(fixtures): add 2 real-snapshot fixtures for v0.2.8 eval harness
```

(Task 10.1 — 4 synthetic fixtures — is in earlier commit a416332 from session 2.)
