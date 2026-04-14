# Scenario: full Phase 12 release gate (final checkpoint, rerun after xcodeproj fix)

## Context

This scenario was updated on 2026-04-14 after a rerun of the release gate on a fixed candidate. The **authoritative release gate artifact** for v0.2.8 is now `docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json` (produced on candidate `490fa72`).

The earlier `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json` (on candidate `5ac5efb`) is **retained as audit history** but is NOT the release-decision artifact. That run passed all 8-way binding checks at release-gate-tool level, but its candidate state had incomplete Xcode project membership that caused `xcodebuild test` to fail on PR #17 CI. The 2026-04-14 rerun is on the post-fix candidate where both SwiftPM and Xcode dual-build paths are green.

**Tag target for v0.2.8**: `57cd04f` (the 2026-04-14 artifact commit). The old `cc4a2ce` artifact commit remains in history but is not the release target.

## Steps

1. Confirm BOTH release gate artifacts exist side-by-side in-repo:
   ```bash
   ls -la docs/eval/gate-runs/
   ```
   Expected: both files present:
   - `2026-04-13-v0.2.8-5ac5efb3.json` (audit history)
   - `2026-04-14-v0.2.8-490fa72e.json` (authoritative for release decision)

2. Inspect the NEW artifact critical fields:
   ```bash
   python3 -c "
   import json
   a = json.load(open('docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json'))
   for k in ['mode','tagLabel','commitSHA','gateResult','provider','model','temperature','dslSchemaVersion','promptBuilderHash']:
       print(f'{k}: {a[k] if k != \"promptBuilderHash\" else a[k][:40]+\"...\"}')"
   ```
   Expected output:
   - `mode: release`
   - `tagLabel: v0.2.8`
   - `commitSHA: 490fa72e0f628f254c4bb6a3225b731074507c46`
   - `gateResult: PASS`
   - `provider: dashscope`
   - `model: qwen-plus`
   - `temperature: 0`
   - `dslSchemaVersion: 1`
   - `promptBuilderHash: sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a...`

3. Confirm all 6 fixtures passed in the new artifact:
   ```bash
   python3 -c "
   import json
   a = json.load(open('docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json'))
   for r in a['fixtureResults']:
       print(f'{\"PASS\" if r[\"passed\"] else \"FAIL\"}: {r[\"id\"]}')"
   ```
   Expected: 6 PASS lines (real-snapshot-01, real-snapshot-02, synthetic-cross-version-range-01, synthetic-empty-progress-01, synthetic-tail-bias-01, synthetic-version-hallucination-01).

4. **Process gotcha (unchanged from previous run)**: `check-artifact` must be run with git HEAD positioned at the tag target commit (`57cd04f`), not at the branch tip. Subsequent verify/doc commits on top of the artifact commit push the branch tip past the target, and at the branch tip `git rev-parse HEAD^` no longer equals the artifact's commitSHA. `check-artifact` fails with a false-FAIL at the branch tip in that state.

   Correct invocation — temporarily detach at the artifact commit:
   ```bash
   git checkout 57cd04f
   swift run eval-harness check-artifact --tag v0.2.8
   # Expected: ✓ Gate check passed for tag 'v0.2.8'
   # Expected commitSHA echoed: 490fa72e0f628f254c4bb6a3225b731074507c46
   # Expected provider/model: dashscope / qwen-plus
   git checkout feature/v0.2.8-ai-eval
   ```

   Additional note on strict unique match: two artifacts now live in `gate-runs/` both with `tagLabel=v0.2.8` and `mode=release`. The `commitSHA` filter discriminates them — at the 2026-04-14 artifact commit, `HEAD^ == 490fa72`, so only the 2026-04-14 artifact matches the triple. The 2026-04-13 artifact (commitSHA `5ac5efb`) is correctly filtered out. The strict unique match behavior is preserved.

5. Confirm that the parent of the tag target commit is the 2026-04-14 candidate (does NOT require checkout):
   ```bash
   git rev-parse 57cd04f^
   ```
   Expected: `490fa72e0f628f254c4bb6a3225b731074507c46`

6. Confirm the old artifact is still preserved intact:
   ```bash
   python3 -c "
   import json
   a = json.load(open('docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json'))
   print('commitSHA:', a['commitSHA'])
   print('gateResult:', a['gateResult'])"
   ```
   Expected:
   - `commitSHA: 5ac5efb37656812985c2ac3c7fed61e3286295df`
   - `gateResult: PASS`

7. Confirm PR #17 CI is green on the fix commit:
   ```bash
   gh pr checks 17 --repo MedivhStory/ClaudeSessionHub
   ```
   Expected: `SPM Unit Tests pass` and `Xcode Unit + UI Tests pass`, both on run `24399202510` (the run for commit `490fa72`).

8. Full test suite:
   ```bash
   swift test 2>&1 | grep 'Executed [0-9]\{3\} tests' | tail -2
   ```
   Expected: 339 tests, 0 failures.

9. Xcode unit test suite on the fixed project:
   ```bash
   xcodebuild test -project ClaudeSessionHub.xcodeproj -scheme ClaudeSessionHub -destination 'platform=macOS' -only-testing:ClaudeSessionHubTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
   ```
   Expected: `** TEST SUCCEEDED **`, 155 tests.

## Expected

- Both release gate artifacts present in `docs/eval/gate-runs/`, side-by-side, neither overwritten
- New artifact (`2026-04-14-v0.2.8-490fa72e.json`) commits to `490fa72` candidate, mode=release, gateResult=PASS, 6/6 fixtures pass
- Old artifact (`2026-04-13-v0.2.8-5ac5efb3.json`) preserved intact as audit history
- `check-artifact` 8-way binding passes at the 2026-04-14 artifact commit (`57cd04f`)
- Tag target commit is `57cd04f` (the 2026-04-14 artifact commit); its parent is the 2026-04-14 candidate `490fa72`
- Unit tests unchanged (339 passing in SwiftPM, 155 passing in Xcode unit target)
- PR #17 CI green (both SPM and Xcode jobs)
- Fresh verify-run directory at `docs/verify/runs/2026-04-14-phase12-rerun-after-xcodeproj-fix/`; old `docs/verify/runs/2026-04-14-phase12-release-gate/` directory left untracked, not migrated

## Notes

- This is the rerun checkpoint, superseding the earlier 2026-04-13 Phase 12 checkpoint for release decision purposes
- Tag creation requires explicit user approval after this verification
- The 3 earlier LLM quality fixes from the 2026-04-13 run are still in effect (ae90153, 9d9bde6, 5ac5efb) — none of them were reverted or modified by the xcodeproj fix
- `promptBuilderHash` is identical between the 2026-04-13 and 2026-04-14 artifacts, confirming the xcodeproj fix did not touch any prompt source (the hash depends on LLMPrompts source + 3 system prompts, none of which changed between the two runs)
- Release-mode run on 2026-04-14 was a SINGLE run, PASS on first attempt (no "run until green" retry pattern, consistent with the fail-closed spec philosophy)
- The old 2026-04-13 run is not erased because the fail-closed spec's audit philosophy requires preserving the full history, not just the final green record
