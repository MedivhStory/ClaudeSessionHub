# Verification Handoff: Phase 12 RERUN — Final release gate (pre-tag)

**Branch:** feature/v0.2.8-ai-eval
**Commit SHA:** 57cd04f6563404d9b0d82d998ed002575ddfaad5
**Handoff time:** 2026-04-14T13:03:34Z
**Phase:** 12 RERUN — End-to-end release gate (🛑 FINAL verify checkpoint on the post-xcodeproj-fix state)

## Why this is a RERUN

The 2026-04-13 Phase 12 run (candidate `5ac5efb`, artifact commit `cc4a2ce`) passed all 8-way binding checks under the release gate tool but was built on an **incomplete Xcode project membership state**. SPM Unit Tests were green, but Xcode Unit + UI Tests on PR #17 CI failed with "cannot find type" errors because 4 Phase 1-3 production Swift files and 4 corresponding Xcode test files had never been added to `ClaudeSessionHub.xcodeproj/project.pbxproj`. The release gate tool did not notice this because it validates LLM output against fixtures, not the dual-build system consistency.

Commit `490fa72` (`fix(xcodeproj): add Phase 1-3 files to Xcode project target membership`) added the 8 missing file references and unblocked both CI jobs. This manifest covers the **fresh release-mode run on that fixed candidate state**, produced at commit `57cd04f`, with its artifact at `docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json`.

**The 2026-04-13 artifact is retained side-by-side** in `docs/eval/gate-runs/` for audit-history completeness, per the fail-closed spec's philosophy of preserving the record of what gate runs actually happened. The 2026-04-14 artifact is the authoritative one for the release decision.

## 1a. What changed

### Affected components (since the previous Phase 12 handoff at commit `b33d9d0`)

- `ClaudeSessionHub.xcodeproj/project.pbxproj` (commit `490fa72`):
  - Added 4 production file references targeting `ClaudeSessionHub` main target:
    - `Sources/ClaudeSessionHub/Models/VersionMention.swift`
    - `Sources/ClaudeSessionHub/Models/MilestoneEntry.swift`
    - `Sources/ClaudeSessionHub/Services/VersionMentionExtractor.swift`
    - `Sources/ClaudeSessionHub/Services/MilestoneSampler.swift`
  - Added 4 test file references targeting `ClaudeSessionHubTests` test target:
    - `Tests/XCTests/Models/VersionMentionTests.swift`
    - `Tests/XCTests/Models/MilestoneEntryTests.swift`
    - `Tests/XCTests/Services/VersionMentionExtractorTests.swift`
    - `Tests/XCTests/Services/MilestoneSamplerTests.swift`
  - 32 line additions: 8 PBXBuildFile + 8 PBXFileReference + 8 PBXGroup refs + 8 PBXSourcesBuildPhase refs
  - Used ID scheme `A0280001-A0280008` / `B0280001-B0280008` for v0.2.8
- `docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json` (commit `57cd04f`):
  - New release gate artifact from a fresh `swift run eval-harness live --release --tag v0.2.8` execution on candidate commit `490fa72`
  - mode=release, gateResult=PASS, 6/6 fixtures passed
  - commitSHA=`490fa72e0f628f254c4bb6a3225b731074507c46`
  - promptBuilderHash identical to the 2026-04-13 artifact (prompts unchanged between runs)

### Spec references

- Implements end-to-end: §2.5 (release artifact schema), §6.1 (gate-runs directory), I-2 (two-layer verification), I-3 (canonical provider locked), I-4 (8-way binding), I-5 (promptBuilderHash definition), I-14 (version clause zero-detection), I-15 (release gate mechanical + process rule)

### Change description (this rerun only)

- Fresh `live --release --tag v0.2.8` execution on candidate `490fa72`
- Single run, no retry pattern
- All 6 fixtures PASS: real-snapshot-01, real-snapshot-02, synthetic-cross-version-range-01, synthetic-empty-progress-01, synthetic-tail-bias-01, synthetic-version-hallucination-01
- `check-artifact --tag v0.2.8` passed all 8 binding checks at the new artifact commit `57cd04f`:
  - mode == release
  - commitSHA (`490fa72e0f628f254c4bb6a3225b731074507c46`) == parent of the artifact commit
  - promptBuilderHash == current LLMPrompts hash
  - dslSchemaVersion == 1
  - provider == dashscope
  - model == qwen-plus
  - temperature == 0
  - gateResult == PASS

### Scenarios

- `docs/verify/scenarios/004-sampling-library-complete.md` (Phase 4 checkpoint, previously verified)
- `docs/verify/scenarios/007-build-plugin-hasher.md` (Phase 7 checkpoint, previously verified)
- `docs/verify/scenarios/010-fixture-set.md` (Phase 10 checkpoint, previously verified)
- `docs/verify/scenarios/012-release-gate.md` (this checkpoint — updated for the rerun)

## 1b. Environment requirements

### LLM mode

- `disabled` — this handoff is read-only verification. The live run already completed; its artifact is committed. No further LLM invocations needed for the scenario steps.

### Required environment variables

- none for the verification scenario steps

### Network

- `offline OK` — verification is file reads + local swift test + local check-artifact

### Xcode version

- Xcode 26.4 or newer (v0.2.8 baseline). The PR #17 CI uses Xcode 16.2 (macOS-15 runner) which also works.

### MCP availability assumptions

- none beyond baseline

### Pre-flight installs

- none

### macOS permission requirements

- none beyond macos-automator baseline

## Notes for verifier

### Critical invariants to spot-check

1. **New artifact commitSHA matches candidate**: `2026-04-14-v0.2.8-490fa72e.json` has commitSHA `490fa72e0f628f254c4bb6a3225b731074507c46`. The artifact commit is `57cd04f`; its parent is `490fa72`, the candidate. `git rev-parse 57cd04f^` should equal the artifact's commitSHA.
2. **Old artifact preserved side-by-side**: `2026-04-13-v0.2.8-5ac5efb3.json` is still present at the original location with its original content (108 lines, commitSHA `5ac5efb37656...`). It is NOT the release-decision artifact anymore — it is audit history. The 2026-04-14 artifact supersedes it for the release decision.
3. **PR #17 CI green on 490fa72**: GitHub Actions run `24399202510` — SPM Unit Tests pass 51s, Xcode Unit + UI Tests pass 3m47s. This is the dual-build validation that the 2026-04-13 candidate lacked.
4. **check-artifact strict unique match still works**: with 2 artifacts in `docs/eval/gate-runs/` both having `tagLabel=v0.2.8` and `mode=release`, the commitSHA discriminator ensures only the new one matches at the new artifact commit. Verified: `swift run eval-harness check-artifact --tag v0.2.8` at artifact commit `57cd04f` returns exit 0.
5. **promptBuilderHash unchanged**: both artifacts have `sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a7b5f65f1294db34b000cb384`. This confirms that the xcodeproj fix did NOT alter any LLMPrompts source or system prompt content. The two artifacts differ only in commit SHA — the semantic prompt state is byte-identical.

### Tag target for this rerun

- **Tag target commit (proposed, pending your decision)**: `57cd04f` — the 2026-04-14 artifact commit
- **Candidate commit (parent of tag target)**: `490fa72` — the xcodeproj fix commit
- **Old tag target (not to be used for release, left in history only)**: `cc4a2ce` — the 2026-04-13 artifact commit
- **Current v0.2.8 tag**: still points at `cc4a2ce` (the old target). Retag decision is reserved for user approval after this checkpoint passes.

### Running `check-artifact` at the branch tip has the same HEAD^ gotcha as before

After subsequent verify/doc commits land on top of `57cd04f`, the branch tip will be past the artifact commit and `git rev-parse HEAD^` will no longer equal the artifact's commitSHA. The verify team must:
```bash
git checkout 57cd04f
swift run eval-harness check-artifact --tag v0.2.8
# expect: ✓ Gate check passed for tag 'v0.2.8'
# expect commitSHA: 490fa72e0f628f254c4bb6a3225b731074507c46
git checkout feature/v0.2.8-ai-eval
```

This matches the documented gotcha in `docs/verify/scenarios/012-release-gate.md`.

### Full commit range for the fix + rerun (since previous handoff `b33d9d0`)

```
b33d9d0 docs(verify): replace relative HEAD refs with absolute SHAs (previous handoff tip)
490fa72 fix(xcodeproj): add Phase 1-3 files to Xcode project target membership
57cd04f chore(eval): v0.2.8 release gate rerun artifact (post xcodeproj fix)
```

### Out of scope for this rerun

- **Tag rewrite / retag of v0.2.8**: reserved for user approval after this verify checkpoint passes
- **Old artifact `2026-04-13-v0.2.8-5ac5efb3.json`**: not to be deleted, modified, or overwritten — it remains in the repo as audit history of the incomplete-state run
- **`release.yml` trigger issue**: flagged, not fixed. `.github/workflows/*` is not tracked in this branch, so nothing to edit here. Separate follow-up.
- **Stale untracked `docs/verify/runs/2026-04-14-phase12-release-gate/accept-decision.md`**: leave untracked, not committed. A fresh verify-run directory is created for this rerun (see below).

### Fresh verify-run directory

A new directory `docs/verify/runs/2026-04-14-phase12-rerun-after-xcodeproj-fix/` has been created for the verify team to place its output for this rerun. The stale `docs/verify/runs/2026-04-14-phase12-release-gate/` directory (from before the xcodeproj fix) is deliberately left untracked and untouched — not migrated, not deleted.

## Commit state at handoff time

- **Tag target commit (proposed)**: `57cd04f6563404d9b0d82d998ed002575ddfaad5` (the 2026-04-14 artifact commit)
- **Candidate commit** (parent of tag target): `490fa72e0f628f254c4bb6a3225b731074507c46`
- Branch: `feature/v0.2.8-ai-eval`
- Branch tip at handoff is `57cd04f` (this manifest update will push the branch tip further)
- Old release-gate artifact commit (preserved, NOT the new tag target): `cc4a2cec899586db4c0386f410cda608aac8816c`
- Old candidate commit (preserved, NOT the new candidate): `5ac5efb37656812985c2ac3c7fed61e3286295df`
- Pushed to origin: (this manifest update push is pending)

All SHA references in this manifest are absolute. Relative HEAD/HEAD^/HEAD^^ narrative references are avoided to prevent stale positioning as the branch advances.
