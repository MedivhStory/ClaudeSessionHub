# Scenario: full Phase 12 release gate (final checkpoint)

## Steps

1. Confirm the release artifact exists in-repo:
   ```bash
   ls -la docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json
   ```
   Expected: file exists, committed at `cc4a2ce`.

2. Inspect artifact critical fields:
   ```bash
   python3 -c "
   import json
   a = json.load(open('docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json'))
   for k in ['mode','tagLabel','commitSHA','gateResult','provider','model','temperature','dslSchemaVersion','promptBuilderHash']:
       print(f'{k}: {a[k] if k != \"promptBuilderHash\" else a[k][:40]+\"...\"}')"
   ```
   Expected output:
   - `mode: release`
   - `tagLabel: v0.2.8`
   - `commitSHA: 5ac5efb37656812985c2ac3c7fed61e3286295df`
   - `gateResult: PASS`
   - `provider: dashscope`
   - `model: qwen-plus`
   - `temperature: 0`
   - `dslSchemaVersion: 1`
   - `promptBuilderHash: sha256:6e095c7101ae708f4c0affde05a6237715ba5a9a...`

3. Confirm all 6 fixtures passed in the artifact:
   ```bash
   python3 -c "
   import json
   a = json.load(open('docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json'))
   for r in a['fixtureResults']:
       print(f'{\"PASS\" if r[\"passed\"] else \"FAIL\"}: {r[\"id\"]}')"
   ```
   Expected: 6 PASS lines.

4. Run `check-artifact` to verify 8-way binding on HEAD (artifact commit) vs HEAD^ (candidate):
   ```bash
   swift run eval-harness check-artifact --tag v0.2.8
   ```
   Expected: `✓ Gate check passed for tag 'v0.2.8'`
   Expected commitSHA echoed: `5ac5efb37656812985c2ac3c7fed61e3286295df`
   Expected provider/model: `dashscope / qwen-plus`

5. Confirm HEAD^ is the candidate commit the artifact claims:
   ```bash
   git rev-parse HEAD^
   ```
   Expected: `5ac5efb37656812985c2ac3c7fed61e3286295df`

6. Full test suite:
   ```bash
   swift test 2>&1 | grep 'Executed [0-9]\{3\} tests' | tail -2
   ```
   Expected: 339 tests, 0 failures.

## Expected

- Release gate artifact at `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json`, committed at `cc4a2ce`, pushed to origin
- All 6 fixtures passing in release mode (not dev mode)
- `check-artifact` 8-way binding passes
- Current branch HEAD is the artifact commit (`cc4a2ce`); HEAD^ is the candidate commit (`5ac5efb`)
- Unit tests unchanged (339 passing)

## Notes

- This is the final verify checkpoint before tag creation
- Tag creation requires explicit user approval after this verification
- The `synthetic-version-hallucination-01` summary leak that was originally failing is now fixed via `versionClauseShared` strengthening (commit `ae90153`)
- The `real-snapshot-02` title tail-bias that was originally failing is now fixed via `baseTitleSystemPrompt` anti-recency language (commit `9d9bde6`)
- Length variance that was causing 2/3 flake has been addressed via hard-cap wording + title compression example pair (commit `5ac5efb`)
- 3 consecutive clean dev-mode runs were observed before release-mode run (reliability evidence)
- Release-mode run was a SINGLE run, PASS on first attempt (no "run until green" retry pattern)
