# Verification Handoff: Phase 4 — Main library signal + sampling complete

**Branch:** feature/v0.2.8-ai-eval
**Commit SHA:** a1317d2ded2d15f55ba62321f718caf9143cc3e1
**Handoff time:** 2026-04-11T15:00:25Z
**Phase:** 4 — readSampledUserTurns rewrite (🛑 first verify checkpoint)

## 1a. What changed

### Affected components

- `Sources/ClaudeSessionHub/Models/VersionMention.swift` (new — Phase 1)
- `Sources/ClaudeSessionHub/Models/MilestoneEntry.swift` (new — Phase 1)
- `Sources/ClaudeSessionHub/Models/SessionSignals.swift` (modified — Phase 1: +versionMentions field)
- `Sources/ClaudeSessionHub/Services/VersionMentionExtractor.swift` (new — Phase 2)
- `Sources/ClaudeSessionHub/Providers/ClaudeProvider.swift` (modified — Phase 2: populate versionMentions in extractSignals tail)
- `Sources/ClaudeSessionHub/Services/MilestoneSampler.swift` (new — Phase 3)
- `Sources/ClaudeSessionHub/Providers/JSONLParser.swift` (modified — Phase 4: readSampledUserTurns rewritten as two-pass streaming)
- `Tests/XCTests/Models/VersionMentionTests.swift` (new, 7 tests)
- `Tests/XCTests/Models/MilestoneEntryTests.swift` (new, 3 tests)
- `Tests/XCTests/Services/VersionMentionExtractorTests.swift` (new, 11 tests)
- `Tests/XCTests/Services/MilestoneSamplerTests.swift` (new, 27 tests: 13 adaptiveK + 14 sample)
- `Tests/XCTests/Providers/ClaudeProviderTests.swift` (modified, +4 integration tests)
- `Tests/XCTests/Providers/JSONLParserTests.swift` (modified, +12 new behavior tests)

### Spec references

- Implements: §3.1, §3.2, §3.3, §4.1, §4.2, §4.3, §4.4, §5.1, §5.2, §5.3, §5.4
- Invariants satisfied: I-11 (responsibility boundaries — extractor is pure function; population locked to ClaudeProvider tail), I-12 (readSampledUserTurns memory contract ≤ K + transient; no readAllEntries call), I-13 (MilestoneEntry.reasons non-empty + deterministic 4-case sort order)

### Change description

- New `VersionMention` / `SourceRef` / `SourceKind` pure data model with custom Codable decoder enforcing `(kind == .history) ⇔ (index != nil)` invariant
- New `MilestoneEntry` with 4-case `Reason` enum (firstEntry / lastEntry / versionAnchor / timeFill); short-session middle entries reuse `.timeFill(bucket: i, totalBuckets: history.count)` — no `shortSessionEntry` drift
- New `VersionMentionExtractor` scans 6 signal sources in priority order (taskSubject → firstUserIntent → lastUserIntent → taskDescription → history → lastAssistantProgress) with strict semver regex `(?i)v?\d+\.\d+(\.\d+)?(-[A-Za-z0-9.]+)?`; three-level deterministic sort (scanOrder asc, occurrenceCount desc, normalized asc)
- `ClaudeProvider.extractSignals(for:)` now populates `signals.versionMentions` at the tail (single call site, I-11)
- New `MilestoneSampler.sample` implements version-anchor + time-uniform fill algorithm with adaptive K (floor=4, ceiling=8, divisor=10), short-session branch (return-all with stacked reasons), long-session branch (first/last + version anchors + Phase 3 time fill), mandatory-exceeds-K truncation (protect first/last, then top anchors by occurrenceCount desc / normalized asc), and deterministic `sortReasons` helper
- `JSONLParser.readSampledUserTurns` rewritten as two-pass streaming (Pass 1: byte-scan line count; Pass 2: bucket-center selection with tie-prefers-earlier; EOF flush for unterminated final line); no longer calls `readAllEntries`; retained parsed entries ≤ K + 1 transient

### Scenarios

- `docs/verify/scenarios/001-models-core.md` (Phase 1, non-checkpoint reference)
- `docs/verify/scenarios/002-version-mentions.md` (Phase 2, non-checkpoint reference) — **NOTE: scenarios 001, 002, 003 were written conceptually but Phase 1/2/3 being non-checkpoint phases, only 004 exists on disk for this checkpoint handoff**
- `docs/verify/scenarios/004-sampling-library-complete.md` (this checkpoint)

## 1b. Environment requirements

### LLM mode

- `disabled` — this checkpoint exercises only the pure-Swift signal + sampling layer. No LLM invocation. `LLMEnhancer` / `LLMClient` / real API calls are not touched by any scenario in this handoff.

### Required environment variables

- none

### Network

- `offline OK` — all tests run locally against temp files and in-memory data structures

### Xcode version

- Xcode 26.4 or newer (v0.2.8 baseline)

### MCP availability assumptions

- none beyond baseline (macos-automator + playwright user-scope available but unused at this checkpoint)

### Pre-flight installs

- none

### macOS permission requirements

- none beyond macos-automator baseline

## Notes for verifier

- **Stale SourceKit diagnostics are expected**: the IDE indexer may show "cannot find VersionMention in scope" / "no member versionMentions" errors for files that reference the new types. These are false positives — `swift test` (the authoritative compiler) reports 0 failures. Ignore IDE diagnostics; trust `swift test`.
- Full test suite: 229 tests, 0 failures. Baseline before v0.2.8 was 165. Delta +64 new tests through Phase 4.
- Commit range for this checkpoint: `955ddc7` (scaffold) through `a1317d2` (readSampledUserTurns rewrite). 9 commits total.
- Phase 5 (LLMPrompts consumer refactor) is gated on this checkpoint's approval. Phase 5 completes the user-visible prompt-layer change; until then, the prompt builder still uses the v0.2.7 inline keyword filter even though the structured signals are populated upstream.
- Test file `Tests/XCTests/Providers/JSONLParserTests.swift` contains 12 new tests. The plan text advertised 13 but the spec block listed 12 function bodies — this is a plan drafting off-by-one, not a missing test. All 12 planned tests are present and passing.
- **4-case Reason enum is load-bearing** (I-13). A previous round of spec revision drift introduced a `.shortSessionEntry` 5th case which the user caught and reverted. The verifier should confirm zero `shortSessionEntry` / `中间条目` occurrences anywhere in Sources/ or Tests/.

## Commit range

```
955ddc7 chore(verify): add verification workflow scaffold
e103310 feat(models): add VersionMention, SourceRef, SourceKind
f91b4f3 feat(models): add MilestoneEntry with 4-case Reason enum
f1c853c feat(signals): add versionMentions field to SessionSignals
326510f feat(signals): add VersionMentionExtractor with 6-source scan order
9c09191 feat(provider): populate versionMentions in extractSignals
9b606e1 feat(sampler): add MilestoneSampler.adaptiveK
f455051 feat(sampler): MilestoneSampler.sample algorithm
a1317d2 perf(parser): rewrite readSampledUserTurns as two-pass streaming
```
