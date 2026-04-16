# Phase 12 rerun verify-run directory

**Status: authoritative release-authorizing audit for v0.2.8.** The earlier
`../2026-04-14-phase12-release-gate/accept-decision.md` is preserved in-repo as
superseded audit history (see that directory's `README.md` for why). This
rerun's `accept-decision.md` is the one that authorized the v0.2.8 ship.

This is the verify-run output directory for the **Phase 12 RERUN** after the xcodeproj membership fix.

## Context

- Tag target commit: `57cd04f` (2026-04-14 release gate artifact commit)
- Candidate commit: `490fa72` (xcodeproj fix commit)
- Authoritative release artifact: `docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json`
- Manifest: `docs/verify/handoff-manifest.md` (at branch tip)
- Scenario: `docs/verify/scenarios/012-release-gate.md` (updated 2026-04-14 for rerun)

## Why rerun

The 2026-04-13 Phase 12 run was on candidate `5ac5efb`, which had incomplete Xcode project membership. PR #17 CI failed Xcode Unit + UI Tests with "cannot find type" errors because 4 production Swift files and 4 test files added in Phase 1-3 had never been added to `ClaudeSessionHub.xcodeproj/project.pbxproj`. Commit `490fa72` fixed this, and this rerun is on the fixed state.

The 2026-04-13 artifact `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json` is preserved side-by-side as audit history. The 2026-04-14 artifact supersedes it for release decision purposes.

## Intended contents of this directory

The `cshub-verify` team should place its Phase 12 rerun audit output here, including:
- Scenario 012 step-by-step pass/fail report
- Any additional commit-scope audit notes
- The final accept/reject decision for this rerun

## Not related to

The old directory `docs/verify/runs/2026-04-14-phase12-release-gate/` holds the verify output from the earlier (pre-xcodeproj-fix) Phase 12 attempt. It was left untracked in the working tree and is deliberately NOT migrated or merged into this directory. Those are two separate verify runs with two separate outcomes.
