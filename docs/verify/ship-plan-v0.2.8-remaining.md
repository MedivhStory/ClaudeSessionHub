# v0.2.8 Remaining Ship Plan (post-rerun)

## Current state (locked facts, do not second-guess)

- Branch: feature/v0.2.8-ai-eval
- Branch tip: 3a00236 (or later, per `git rev-parse HEAD`)
- **Authoritative new tag target**: `57cd04f` (artifact commit, post-xcodeproj-fix)
- **Authoritative new candidate**: `490fa72` (xcodeproj fix commit, parent of 57cd04f)
- **Authoritative new artifact file**: `docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json`
- **Current v0.2.8 tag**: still points to OLD `cc4a2ce` (to be rewritten)
- **Old chain preserved as audit history, must NOT be deleted**:
  - Old artifact: `docs/eval/gate-runs/2026-04-13-v0.2.8-5ac5efb3.json`
  - Old candidate: `5ac5efb`
  - Old artifact commit: `cc4a2ce`
  - Stale untracked verify-run dir: `docs/verify/runs/2026-04-14-phase12-release-gate/` (NEVER commit)

## Remaining steps (in exact order)

### Step 1 — Verify team runs scenario 012 on the rerun chain

- Awaiting team verdict
- Team should audit: new artifact at `2026-04-14-v0.2.8-490fa72e.json`, candidate `490fa72`, tag target `57cd04f`
- Team must run `check-artifact --tag v0.2.8` with HEAD detached at `57cd04f`, NOT at branch tip

### Step 2 — If team PASSES: retag v0.2.8

Execute EXACTLY this sequence:

```bash
# Delete old tag locally
git tag -d v0.2.8

# Delete old tag on remote
git push origin :refs/tags/v0.2.8

# Create new annotated tag on 57cd04f
git tag -a v0.2.8 57cd04f -m "v0.2.8 — AI evaluation harness (corrected after xcodeproj fix)"

# Push new tag to remote
git push origin v0.2.8

# Verify tag now points to 57cd04f
git rev-parse v0.2.8^{commit}
# Expected output: 57cd04f...
```

### Step 3 — Merge PR #17 with MERGE COMMIT (not squash, not rebase)

```bash
gh pr merge 17 --repo MedivhStory/ClaudeSessionHub --merge \
  --subject "Merge v0.2.8 — AI evaluation harness + release gate (post-xcodeproj-fix)" \
  --body "Merges feature/v0.2.8-ai-eval at full audit depth. Tag v0.2.8 points to 57cd04f (the rerun artifact commit). The 2026-04-13 artifact is retained for audit history. See docs/eval/gate-runs/2026-04-14-v0.2.8-490fa72e.json for the authoritative release gate audit trail."
```

### Step 4 — Verify merged state

```bash
git fetch origin
git log origin/main --oneline | head -5  # should show merge commit
git branch -r --contains 57cd04f         # should list origin/main
git rev-parse v0.2.8^{commit}            # should still be 57cd04f
```

### Step 5 — Deferred (NOT for this session)

- Investigate release.yml tag-push trigger (not in this branch)
- Publish GitHub Release from tag v0.2.8
- Memory update about dual-build-system lesson
- Seal ClaudeSessionHub_V0.2.8 workdir

## Hard constraints (must survive context compression)

- DO NOT delete the old artifact 2026-04-13-v0.2.8-5ac5efb3.json
- DO NOT commit the stale docs/verify/runs/2026-04-14-phase12-release-gate/accept-decision.md
- DO NOT use squash or rebase merge on PR #17 (merge commit only)
- DO NOT create v0.2.8.1 — retag v0.2.8 is the chosen strategy
- DO NOT proceed past Step 1 without explicit user approval after team verify report
- The authoritative artifact is at 2026-04-14-v0.2.8-490fa72e.json, NOT 2026-04-13-v0.2.8-5ac5efb3.json
- The authoritative tag target is 57cd04f, NOT cc4a2ce
