# Verification decision — round 01 (experimental team rebuild run)

**Handoff**: `v0.2.8` tag @ commit `57cd04f` (ClaudeSessionHub)
**Round ID**: `2026-04-14-visible-ui-smoke-retry`
**Round**: 1 of max 5 (experimental)
**Decision**: **REJECT** — meta-objective not achieved
**Severity**: RED (test-infrastructure blocker, NOT a v0.2.8 product defect)
**Timestamp**: 2026-04-14T18:10:00+08:00
**Coordinator**: team-lead@cshub-verify (self-bound to coordinator-role.md)

## Scope note

This round is an **experimental validation of the cshub-verify agent team mechanism**, not a release gate for v0.2.8. v0.2.8 is already tagged. The sole meta-objective was: "can the tester subagent, via `macos-automator` MCP, drive the macOS desktop such that the human user visually sees cursor movement, window focus changes, and button clicks?"

This REJECT is about the agent team / test harness, not about ClaudeSessionHub product quality.

## Summary

Tester halted at Step D on a hard blocker: `screencapture` returns a frozen/pinned frame (byte-identical across every capture attempt), making it impossible to visually confirm whether any event injection actually rendered. Steps A (launch), B (window query), and event-injection Steps C (click) and D (keynav) completed without errors from AppleScript, but the meta-objective (visible, photographic proof of UI driving) is unverifiable until the capture channel is fixed.

## Evidence

### Screenshots captured
| # | File | Bytes | MD5 | Taken at step |
|---|------|-------|-----|---------------|
| 1 | `screenshots/01-after-launch.png` | 91131 | `2777cf57f5ca4e0bf441a139939d4766` | A |
| 2 | `screenshots/02-after-sidebar-click.png` | 91131 | `2777cf57f5ca4e0bf441a139939d4766` | C primary |
| 3 | `screenshots/02-alt.png` | 91131 | `2777cf57f5ca4e0bf441a139939d4766` | C fallback |
| 4 | `screenshots/03-session-selected.png` | 91131 | `2777cf57f5ca4e0bf441a139939d4766` | D |
| 5 | `screenshots/activated.png` | 91131 | `2777cf57f5ca4e0bf441a139939d4766` | post-activate sanity |

**All five PNGs are byte-identical** (same MD5).

### Cross-session correlation (load-bearing finding)
The coordinator session ran its own TCC probe in Substep 3.2 at 13:59 (file `/tmp/cshub-tcc-probe-1776189568.png`, 91131 bytes).

```
MD5 (/tmp/cshub-tcc-probe-1776189568.png) = 2777cf57f5ca4e0bf441a139939d4766
```

**The coordinator's probe and all five tester captures produce the exact same MD5.** Two independent Claude Code sessions, separated by ~5 minutes and multiple event injections, produced byte-identical screenshots. This is not a TCC denial (file size is reasonable, not a zero-byte or black-fill failure) — it is a **pinned-frame behavior** in the screencapture path available to this harness's process tree. The classification "🟢 FULL GRANTS" reported in Substep 3.3 was a **false positive** against this run's meta-objective: `screencapture` exits 0 and produces a file, but the file is not a live screen capture.

### Per-step outcomes
| Step | AppleScript / Bash | Event Injection? | Ran Without Error? | Visually Verified? | Notes |
|------|-------------------|------------------|--------------------|---------------------|-------|
| A | `open ... --args --ui-test-mode` | N (launch) | Y | NO (frame frozen) | PID 64198 live |
| B | System Events window query | N (query) | Y | N/A (query, no screenshot needed) | Window "Claude Session Hub" 1528×860 @ (794,404) |
| C | `click at {150,300}` then `key code 125` | Y | Y (returned `menu bar 1`) | NO (frame frozen) | **Coordinate surprise**: (150,300) hit menu bar, implying global-screen origin, not window-local |
| D | `key code 125` + `key code 36` | Y | Y | NO (frame frozen) | HALTED here per "no silent retry" rule |
| E | Settings via ⌘, | — | NOT RUN | — | Halted |
| F | Close via ⌘W | — | NOT RUN | — | Halted |
| G | Rapid ⌘Tab probe | — | NOT RUN | — | Halted |
| H | Clean quit | — | NOT RUN | — | App PID 64198 **still running** |

Tester confirmed via System Events after blocker: app is `frontmost=true, visible=true, 1 window`. So the window server believes the app is on top — yet screencapture does not reflect that state.

### Environment workarounds applied by tester
- None. Tester correctly stopped on first blocker instead of improvising.

### Policy note from tester
Tester reported "subagent policy forbids .md reports," so the structured `report.md` was not written and findings were delivered as a team message instead. This is a documentation gap for the tester-role.md spec — the role doc currently instructs tester to write report.md, but the subagent runtime appears to block this pattern. Worth logging for v0.2.9 role-doc revision.

## Issues

### Blocker 1: Screen capture channel pinned
- **Severity**: BLOCKER (for meta-objective, not for v0.2.8 product)
- **Where**: Any `screencapture` invocation from either coordinator or tester session in this terminal's process tree
- **Observed**: Every PNG produced is byte-identical (MD5 `2777cf57f5ca4e0bf441a139939d4766`, 91131 bytes, 2560×1440)
- **Expected**: Live screen contents reflecting the current desktop state at the moment of capture
- **Evidence**: 5 tester captures + 1 coordinator probe all hash to the same MD5 across a ~5-minute window and multiple confirmed AppleScript injections
- **Reproduction**: In this terminal's process tree, run `screencapture -x /tmp/foo.png` twice with any delay — both outputs hash identically even if the visible desktop has changed
- **Not yet determined**: whether this is (a) a TCC-adjacent macOS behavior pinning screencapture after first permission check, (b) a Claude Code harness sandboxing layer, or (c) a kernel-level frame cache. **Not the coordinator's job to debug this** — flagged for user / reflection doc.

### Blocker 2: `click at {x,y}` coordinate space surprise (secondary)
- **Severity**: MAJOR (not a blocker on its own, but relevant for v0.2.9 tester-role rewrite)
- **Where**: Tester Step C
- **Observed**: `click at {150, 300}` scoped inside `tell process "ClaudeSessionHub"` returned `menu bar 1 of application process ClaudeSessionHub` — indicating the coordinate was interpreted in **global screen space**, not window-local space
- **Implication**: Future rounds must target via `click UI element` (after enumerating via `entire contents of window 1`), or compute absolute coordinates as `window_position + intended_offset`
- **Not a v0.2.8 defect**: this is a test-author understanding issue, not a product issue

### Orphan process
- **PID 64198 (ClaudeSessionHub with `--ui-test-mode`)** is still running because Step H was not reached. Coordinator does not kill processes per role constraints. **User decision needed**: kill it manually or leave it for re-run.

## Verdict

**REJECT** with **RED** status on the meta-objective.

**Reasoning**:
1. Coordinator-role.md rule: "When in doubt, REJECT and let main agent investigate. False accepts are worse than false rejects."
2. Coordinator-role.md rule: "Never claim something works without Tester's evidence to back it up."
3. Tester produced **zero visual evidence** that any event injection rendered. AppleScript return values are not sufficient — they prove the System Events bridge accepted the command, not that the OS window server processed it visibly. Meta-objective requires photographic proof.
4. Four of eight steps did not execute.

**What this REJECT does NOT mean**:
- It does NOT mean v0.2.8 has a defect. The v0.2.8 .app launched cleanly under `--ui-test-mode`, responded to `System Events` queries with sensible values, and is still running.
- It does NOT mean `macos-automator` MCP is broken. `execute_script` delivered every AppleScript command successfully and returned meaningful results.
- It does NOT trigger the rounds counter in the sense of coordinator-role.md — this is an experimental team-rebuild run, not a v0.2.8 release verification.

## Suggested focus for v0.2.9 follow-up

1. **Screen capture channel**: investigate why `screencapture` returns a frozen frame in this harness process tree. Candidates to try in v0.2.9:
   - Alternate capture path: JXA + `CGWindowListCreateImage` via `execute_script` — runs under a different TCC context and may bypass whatever layer is pinning `screencapture`.
   - Per-window capture: `screencapture -l <windowID>` targeting the app's window ID specifically.
   - Spawn capture via a helper app the user explicitly grants Screen Recording to.
2. **Coordinate space**: rewrite tester-role.md Step C guidance to use UI-element targeting (`click UI element …`) or explicitly compute absolute coords from window position, and document that `click at {x,y}` inside `tell process` is **global screen space**, not window-local.
3. **Role-doc / runtime mismatch**: document that subagent runtime blocks `.md` report writing and update tester-role.md to specify "report via team message" as the primary channel, with filesystem writes as optional supplementary artifacts.
4. **Substep 3.3 TCC classification methodology**: the current probe ("file created, non-zero size") is insufficient. Replace with a **live delta probe**: take two captures separated by a forced visible state change (e.g., move a window, toggle dark mode) and MD5-compare. Same-MD5 = pinned frame = probe fails.
5. **TeamCreate topology finding**: the coordinator role is played by the lead session, not a separately spawned teammate. Role docs should be rewritten to reflect hub-and-spoke, not peer topology, of Claude Code's experimental agent teams.

## Round counter
- Previous rounds on this experimental validation: 0
- This round: 1
- Max rounds remaining: 4
- **Escalation note**: because this is experimental team validation (not v0.2.8 release gating), the rounds counter is advisory only. Next action is for the user to decide whether to re-run after fixing the capture channel, or declare the agent-team mechanism needs a different approach before further rounds.

---

## β Retry Result — Human-Observer Fallback (2026-04-14 18:16 UTC)

**Status**: Appended, NOT a replacement. The REJECT section above is preserved as the historical machine-evidence verdict; this section documents an **upgrade to YELLOW** based on subjective human-observer evidence after the machine-evidence channel was ruled out.

### What changed since the REJECT
After the REJECT was written, the user directed a reduced-evidence β continuation:
1. Orphan PID 64198 cleaned up via `pkill -TERM -x ClaudeSessionHub` (confirmed empty).
2. Fresh launch: new PID 74941 via `open ... --args --ui-test-mode`.
3. Tester re-dispatched with explicit instructions to execute Steps E–H via `execute_script` only, with **no screencapture attempts** of any kind. The user (seated at the screen as human observer) would supply visual evidence.

### Framework quirk: tester-2 suffix
The re-dispatch used the `Agent` tool with `team_name: cshub-verify, name: tester`. Because the first tester teammate was still registered in the team as idle, the framework auto-renamed the spawn to `tester-2@cshub-verify`. The team now has 3 members (team-lead, tester idle, tester-2 active). This is a **soft violation of the "NO new teammates spawned" hard constraint** — semantically it is still the tester role, but structurally it is a new teammate slot. The alternative would have been `SendMessage({to: "tester", ...})` to wake the idle original instead. Flagged as a v0.2.9 role-doc clarification item (see follow-ups below). The user's instruction explicitly named the Agent tool, so the coordinator interpreted "dispatch" literally and chose Agent; in retrospect SendMessage may have been the intended semantic.

### Tester-2 execution report (verbatim-quoted fields)
| Step | AppleScript | Return | Post-step sleep honored? |
|------|-------------|--------|---------------------------|
| E    | `tell app to activate` + `keystroke "," using command down` | empty (expected for activate/keystroke) | NO — background `sleep 2` started but next step kicked off before it completed |
| F    | `keystroke "w" using command down` | empty (expected) | NO — same background-sleep race as E |
| G    | `keystroke tab using command down` ×2 with 0.3s delay | empty (expected) | NO — same |
| H    | `tell application "ClaudeSessionHub" to quit` | empty (expected) | YES — final `sleep 2` completed serially before `pgrep` |
| H-check | `pgrep -x ClaudeSessionHub` | **empty** → `clean shutdown confirmed` | — |

**Timing deviation impact**: because Steps E–F–G ran with sub-second inter-step gaps (not the specified 2s dwell), the user likely saw Settings flicker open-then-close rather than dwell open. Tester-2 self-flagged this before the user's observation period ended.

### Human observer responses (verbatim from user)
| Step | Expected observation | User answer |
|------|----------------------|-------------|
| E    | ClaudeSessionHub gained focus, Settings window appeared | **YES — visually confirmed** |
| F    | Settings window closed | **YES — visually confirmed** |
| G    | Rapid ⌘-Tab focus flicker (two app switches ~0.3s apart) | **UNRESOLVABLE — observation channel artifact** |
| H    | ClaudeSessionHub window closed and dock icon disappeared | **YES — visually confirmed AND machine-confirmed via empty `pgrep`** |
| (cursor motion, coord add-on) | Any visible cursor movement during event injection | Not consciously observed — user was not watching for it. **Not a NO, just unobserved.** |

### Step G observation-channel analysis
The user is connected to this machine via **remote desktop**. Their local OS intercepts the ⌘-Tab key combination before it reaches the remote display, so even if tester-2's ⌘-Tab `keystroke using command down` was correctly delivered to the remote `System Events` and processed by the remote macOS window server, the user cannot observe the resulting focus flicker through their remote-desktop channel. **This is not evidence that tester-2's injection failed.** It is a limitation of the observation topology. Step G remains INCONCLUSIVE in both directions: we have no evidence it succeeded, and no evidence it failed.

### Cross-mechanism evidence consistency (load-bearing for the upgrade)
Event injection was confirmed through **three independent AppleScript mechanisms** across the β run:

1. **`activate` + `keystroke ","`** (Step E) → user saw Settings open ✅
2. **`keystroke "w" using command down`** (Step F) → user saw Settings close ✅
3. **`tell application "ClaudeSessionHub" to quit`** (Step H) → user saw window/dock disappear ✅ + `pgrep` empty (machine-confirmed) ✅

Three different AppleScript primitives (activate, keystroke, tell-app-to-quit), each delivered via `mcp__macos-automator__execute_script`, each produced the expected user-visible effect. The probability that all three accidentally coincided with user perception while the underlying mechanism was broken is effectively zero. **AppleScript event delivery to the target app via `macos-automator` MCP is confirmed working** — with the caveat that the confirmation rests on human observation, not machine-captured artifacts.

### Revised verdict: **REJECT → YELLOW (upgraded)**

**Reasoning**:
- The original REJECT was correct under the strict "must have machine-captured photographic evidence" interpretation of the meta-objective. That evidence standard could not be met in this session due to the phantom-frozen-frame `screencapture` bug, which is a **test-infrastructure limitation**, not a product/code defect in v0.2.8 or in `macos-automator` MCP.
- The coordinator-role.md ACCEPT criterion is "test completes without blockers." Under the β run, every executable step that was observable (E, F, H) passed human confirmation, and the only inconclusive step (G) is inconclusive for a reason orthogonal to tester-2 or the agent-team mechanism (remote-desktop key interception).
- YELLOW is the honest middle ground per coordinator-role.md definition: "minor issues, probably fixable in current round, Coordinator may ACCEPT with notes." The "minor issues" here are test infrastructure (phantom capture + observation channel) rather than product behavior, and they are explicitly called out so future readers do not treat this as a clean ACCEPT.
- The **team mechanism itself** — coordinator self-bind → tester dispatch → step execution → report → human relay → verdict writing — executed end-to-end for the first time. That is a first-time full-loop success for the cshub-verify team in its designed role, independent of the v0.2.8 smoke test content.

### Explicit evidence disclaimer
**This YELLOW upgrade is based on SUBJECTIVE human observation only.** The only machine-verified facts in the β run are:
- AppleScript commands returned without raising errors (proves the bridge accepted them, not that they rendered)
- `pgrep -x ClaudeSessionHub` returned empty after Step H (proves clean process shutdown)

No reproducible screenshot, video, accessibility-tree diff, or event log exists to substantiate Steps E/F visually. Any future audit of this decision MUST NOT treat the β section as reproducible validation. It is a one-time fallback anchored to a specific human observer at a specific time.

### Follow-up items for v0.2.9

1. **Investigate phantom frozen-frame `screencapture`** (load-bearing bug). This is the #1 blocker for repeatable visible-UI validation. Candidate diagnostics:
   - Does the frozen frame pin from session start, or from first screencapture call? (take a probe, change the desktop visibly by hand, take another probe, diff)
   - Is it specific to `-x` flag, or does `screencapture -l <windowID>` / `screencapture -t jpg` / JXA `CGWindowListCreateImage` behave the same?
   - Does the pinning survive across terminal restarts (we know it survives across subagent spawns within a session)?
   - Does running `screencapture` **directly** in a non-Claude-Code terminal on the same machine produce a live frame or the same frozen frame?
2. **Clarify tester-2 semantics** in role docs: when the coordinator wants to re-dispatch an idle teammate, is the canonical action `Agent({team_name, name})` (which auto-renames on collision) or `SendMessage({to})` (which wakes the existing idle)? Pick one and document it. Add an explicit assertion in coordinator-role.md and tester-role.md.
3. **Add cursor-motion observation** to the visible-UI smoke checklist. It is a low-level signal that doesn't depend on high-level UI changes and is cheap to inject (e.g., `tell application "System Events" to click at {x, y}` at multiple visible-on-screen coordinates with 1s dwells). The user should be explicitly asked to watch for cursor movement.
4. **Adversarial "remote-desktop-safe" verification**: design a verification method that works regardless of observation channel. Examples:
   - Log-file writes triggered by UI events (a custom event sink in `--ui-test-mode`)
   - In-process XPC probe that reports back on render state
   - Non-keystroke UI drivers (e.g., direct Accessibility `AXPerformAction` via `ax` subprocess)
   - System Events UI-element enumeration diffs before/after injection (no visual capture needed)
5. **Substep 3.3 TCC probe methodology** — replace the current "file created, non-zero size" probe with a **live delta probe**: two captures separated by a forced visible state change (e.g., activate a different app between them), MD5-compare, same-hash = pinned frame = 🔴 probe fails even if file size looks normal.
6. **Coordinator-role.md — "retry vs. cleanup" gray area**: the current rules forbid coordinator from killing processes, but the β run required killing an orphan app to proceed. Clarify that post-blocker cleanup of tester-launched processes is permitted for coordinator (the user issued the explicit `pkill` command, but the rule should be documented for future autonomy).
7. **Pedantic finding**: the original REJECT timestamp `2026-04-14T18:10:00+08:00` was written as coordinator wall clock but appears to be a half-TZ-aware string. Future role docs should specify UTC for all machine-readable timestamps in decision files.

### Orphan process note
A second ClaudeSessionHub instance (**PID 75942**) was launched at user request (via the coordinator's own `open` call, outside the tester flow) after Step H shutdown, so the user could re-observe the app manually. This instance is **still running** at the time this β section is being written. User should decide whether to kill it now or let it persist for further manual inspection.

### β round disposition
- Meta-objective: **PARTIALLY ACHIEVED** — AppleScript event delivery proven (3/3 cross-mechanism), machine-captured visual proof still unavailable (capture channel broken), human-observer visual proof positive for E/F/H.
- Team mechanism end-to-end: **SUCCESS** — first full-loop coordinator↔tester↔user round completed.
- Decision: **YELLOW** (upgraded from RED/REJECT).
- Audit status: subjective evidence only; not reproducible.
