# v0.2.8.3 — Product-line closure release

**Created**: 2026-04-17
**Workspace**: `ClaudeSessionHub_V0.2.8.3/`
**Base**: `origin/main` @ `ab5c19c` (v0.2.8.2 merge commit)
**Philosophy**: Finish and polish existing non-AI capabilities. No new themes.

---

## Core scope (approved)

| Order | ID | Task | Goal | Status |
|-------|----|------|------|--------|
| A | #5 | Rule-engine UUID fallback title UX | Reduce bad UX where sdk-cli sessions show UUID fallback titles | **Partial** — verb pattern expanded; 10+50 window limitation remains |
| B | #10 | Menu-bar AI enhance command | Keyboard discoverability for existing AI enhance capability | Done |
| C | #4 | extractKeyTurns dead-public-API cleanup | Remove zero-caller public surface | Done |
| D | — | formatTokenCount + contextBarColor dead code removal | Opportunistic cleanup | Done |

### #5 limitation note

The expanded English verb pattern (60+ verbs) improves title extraction for sessions
whose first user message starts with common task verbs (e.g. "Generate", "Verify",
"Analyze"). However, the underlying **10+50 entry window limitation** still exists:
sessions where the first meaningful user text is buried past entry index 10 (due to
`queue-operation`, `attachment`, or meta noise at the head) may still fall through to
UUID prefix or produce a title from a non-ideal entry.

A deeper fix would require either expanding the head window or switching `extractSignals`
to a full-scan path (as `extractEnhanceInputs` already does for the AI enhance flow).
This is deferred for later re-evaluation — it is a performance/correctness trade-off
that affects scan latency for large session directories.

## Closed conditional items

### #6 — Keychain scoping (CLOSED)

- **Original report**: "Release build from DerivedData can't read DashScope key, dev build can"
- **Revalidation result**: Not reproducible on shipped v0.2.8.2 build
- **Root cause**: The original "Keychain scoping" framing was a misdiagnosis. The actual shipped-build symptom was the lazy API-key load bug — `isConfigured` returned false on startup because `ensureApiKeyLoaded()` was deferred
- **Resolution**: Fixed by `1500f1c` (eager API-key load at init) in v0.2.8.2
- **FileSecretStore** uses pure filesystem I/O (`~/.claude-hub/.apiKey.secret`), has zero Keychain interaction, and requires no code signing
- **Decision**: Closed. Not a v0.2.8.3 item.

### #11 — `--ui-test-mode` stacked detail-pane (CLOSED)

- **Original report**: "4 sessions stacked in detail pane under `--ui-test-mode`"
- **Classification result**: Intentional test-harness behavior
- **Explanation**: `FixtureProvider` returns 4 deterministic sessions. The app's detail pane is a `SessionListView` with vertically scrolling tiles — all 4 appear so XCUITests can locate them by accessibility identifiers. There is no "single selected session" detail view; the app uses expandable tiles.
- **Decision**: Intentional. Not a bug. Not a v0.2.8.3 item.

## Explicit non-scope

- AI title / summary quality, prompt tuning, extractor strategy improvements
- LLMEnhancer performance / parallelization
- readSampledUserTurns performance
- AI language adaptation
- Font-size configurability
- Agent team infra work
- Release/audit history cleanup, archive tasks, memory/reflection work
- Generic repo housekeeping

These belong to v0.2.9 (AI understanding enhancement) or separate housekeeping lanes.

## Commit discipline

- One task per commit
- Do not bundle unrelated cleanup into feature commits
- Dual-build verification per code-affecting commit: `swift build` + `swift test` + `xcodebuild build` + `xcodebuild test`
- Add or update focused tests where appropriate
