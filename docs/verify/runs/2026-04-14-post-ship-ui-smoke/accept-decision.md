# Accept Decision: v0.2.8 Post-ship UI Smoke Test

**Round ID:** 2026-04-14-post-ship-ui-smoke
**Round type:** Ad-hoc post-ship sanity check (NOT a release gate; does NOT block anything already shipped)
**Tester:** `tester@cshub-verify`
**Coordinator:** team-lead (this document's author)
**App under test:** `dist/ClaudeSessionHub.app` — v0.2.8 tag, commit `57cd04f`, Release config, unsigned
**Companion report:** [`report.md`](report.md)

---

## Decision

**YELLOW — conditional accept for publishing GitHub Release, with required follow-up.**

**Scope note:** This decision does not gate what has already shipped (the v0.2.8 tag and release gate artifact are both already accepted by prior rounds: `2026-04-14-phase12-rerun-after-xcodeproj-fix/accept-decision.md`). This decision only answers the question: *"Given what we now know from the first Phase 2 UI run, is it safe to publish v0.2.8 to users via a GitHub Release, or should we hold for a hotfix first?"*

---

## Summary of findings

- **App-level surface (launch, window, sidebar, session selection, settings, clean shutdown):** green, no bugs observed on this path.
- **Critical v0.2.8 check (Step 2.d: real LLM-enhance on a real session):** **NOT verified** on this run. Two environmental blockers, not app bugs:
  1. Settings in the unsigned `dist/` build has no provider configured (API address / key / model all empty), and the fixtures in the build are hardcoded placeholder content, so there is no way to exercise the real `dashscope` / `qwen-plus` path from the UI without crossing the brief's "no workarounds" line.
  2. `screencapture` fails due to missing Screen Recording TCC entitlement on the automator driver; macOS does not prompt inside an agent-driven run. Zero visual artifacts captured. Only text-based accessibility tree evidence.
- **Accessibility smells discovered in passing (real app-level bugs, not environment issues):**
  1. "AI 理解" card is plain `AXStaticText` with no `AXButton` → VoiceOver users cannot trigger the enhance action even when it is wired up.
  2. Three `AXHeading` elements with missing `value` AND `name` → invisible to screen readers and UI tests.
  3. No menu-bar command for AI enhance → keyboard-only discoverability is poor.
  4. `--ui-test-mode` renders all 4 fixture sessions stacked simultaneously in the detail pane. Unclear if intentional; worth confirming.

---

## Is v0.2.8 safe to publish?

**Yes, with conditions.** The reasoning:

1. **The LLM-side guarantees are already independently verified.** The `2026-04-14-v0.2.8-490fa72e.json` release gate artifact was produced by a fresh `swift run eval-harness live --release --tag v0.2.8` on candidate `490fa72`, against 6 fixtures including `real-snapshot-01` (mixed-context-sanity) and `real-snapshot-02` (subtopic-bias + cross-version-drift). Result: **6/6 PASS on a real DashScope `qwen-plus` run**. The version-leakage reproduction check and the multi-topic robustness check were both performed by that run, just not via the UI. The Phase 12 rerun checkpoint verified that artifact; see `docs/verify/runs/2026-04-14-phase12-rerun-after-xcodeproj-fix/accept-decision.md`.
2. **The dual-build consistency guarantee is already independently verified.** The xcodeproj fix at `490fa72` unblocked the Xcode unit + UI test jobs on PR #17, both green on `fabfaf17` (ancestor-verified to contain the fix). `xcodebuild test` against `ClaudeSessionHubTests` passes 155/0 on the post-fix state.
3. **What this UI run adds on top of those two guarantees is marginal** given the environmental blockers. It confirms the Release binary launches cleanly, the window chrome works, and the app quits without lingering processes. Those are not new information at the same level of criticality as the LLM-side and Xcode build-side guarantees.
4. **The a11y smells are real bugs, but they are not install-blockers.** None of them cause crashes, data loss, or a broken happy-path flow for sighted users with a pointer device. They should be filed as post-ship follow-ups, not gate the publish.

**Conditions on publishing:**

- The GitHub Release description (or a pinned issue) must acknowledge that v0.2.8 was tested at the LLM-eval-harness layer and at the Xcode unit-test layer, but that the first UI-driven functional smoke test was blocked on environment provisioning and will be rerun. This is a *disclosure*, not a *waiver*.
- Two follow-up issues must be filed before or at the time of publishing:
  - **UI smoke test re-run under properly provisioned harness.** Required: DashScope API key staged in the unsigned build's Settings store (or a non-UI mechanism to inject it, e.g. `--args` or a test-only env var), plus Screen Recording TCC granted to the automator driver. This resolves the unknown at the critical Step 2.d.
  - **Accessibility triage for the 4 smells above.** The card-is-not-a-button finding is a real a11y regression vs. platform norms and should be prioritized.

## Recommendation: **publish the GitHub Release**, subject to the two conditions above.

Do not wait for a hotfix. The v0.2.8 shipped artifact is fit for purpose at the evidence level we currently have, and the gaps identified here are about test-harness environment, not app correctness.

---

## What the tester did correctly (process-level)

- **Did not bypass TCC.** Screen Recording permission can be bypassed by invoking `osascript` in ways that sometimes prompt the user, or by other workarounds. The tester correctly followed the brief's "no workarounds" rule and reported the blocker.
- **Did not inject an API key.** The tester could have modified `~/Library/Preferences/…` or the in-bundle defaults to make Step 2.d executable. That would have been a silent workaround in violation of the brief. The tester correctly stopped and reported.
- **Did not force-kill the app on cleanup.** `Cmd-Q` only, then verified with `pgrep`.
- **Did not touch processes outside ClaudeSessionHub.** Honored.
- **Did not modify files outside the scratch and report dirs.** Honored (and, notably, the tester reported that its subagent harness blocked it from writing `report.md` at all; it relayed findings to the coordinator for authoring, which is documented in the report itself).

## What did NOT go smoothly (process-level)

- The tester was unable to write `report.md` directly from its execution context. This was a coordinator-side oversight — a Phase 2 tester agent should have explicit Write permission on its reporting directory. The coordinator (this document's author) wrote the report.md from the tester's verbatim findings relayed via `SendMessage`, and has preserved the raw findings in a fenced blockquote at the end of `report.md` for auditability.
- The screenshot blocker was foreseeable: any time a test harness is expected to produce screenshots, the operator should pre-grant Screen Recording TCC to the automator driver before dispatching the tester. This should be added to Phase 2 pre-flight checks going forward.

---

## Audit team

- **Team:** `cshub-verify`
- **Lead:** team-lead (coordinator / this document's author)
- **tester** — task #1 (UI smoke test walkthrough; reported via SendMessage; shut down after this decision is written)

The tester executed within the brief's hard constraints and correctly stopped at the two environmental blockers rather than papering over them. No other verification work is required from this team for this round.
