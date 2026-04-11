# Scenario: main library signal + sampling changes complete

## Steps

1. Run: `swift test 2>&1 | grep -E "^Test Suite 'All tests'|Executed [0-9]+ tests" | tail -2`
2. Run: `swift test --filter VersionMentionExtractorTests`
3. Run: `swift test --filter MilestoneSamplerTests`
4. Run: `swift test --filter JSONLParserTests`
5. Run: `swift test --filter ClaudeProviderTests`
6. Confirm: `grep -c "readAllEntries" Sources/ClaudeSessionHub/Providers/JSONLParser.swift` returns `1`
   (appears only as its own function definition, not inside `readSampledUserTurns`)
7. Confirm: `grep -n "shortSessionEntry" Sources/ClaudeSessionHub/` returns zero matches
   (4-case Reason enum preserved, no drift reintroduction)

## Expected

- Full suite: 229 tests, 0 failures (baseline 165 + 64 new tests through Phase 4)
- VersionMentionExtractorTests: 11/11 passing
- MilestoneSamplerTests: 27/27 passing (13 adaptiveK + 14 sample algorithm)
- JSONLParserTests: at least 12 new + existing, all passing
- ClaudeProviderTests: at least 4 new integration tests, all passing
- `readAllEntries` count = 1 (function definition only)
- No `shortSessionEntry` anywhere in sources (I-13)
- `MilestoneEntry.Reason` is exactly 4 cases: firstEntry, lastEntry, versionAnchor, timeFill
- Short-session middle entries in tests carry `.timeFill(bucket: i, totalBuckets: history.count)`
  (NOT a hypothetical shortSessionEntry case)
- `readSampledUserTurns` memory contract: retains at most K parsed entries
  (verified by algorithm contract; not a runtime assertion)

## Notes

- This is the first verify checkpoint (cadence rule). Main library signal +
  sampling changes are done; Phase 5 (LLMPrompts consumer refactor) starts
  after verify team approval.
- SourceKit may report stale diagnostics about "cannot find X in scope" for
  new types. These are false positives from the IDE indexer. `swift test`
  is the authoritative compile signal.
- Phase 4 completion is the sampling-layer boundary. Upstream changes
  (VersionMentionExtractor + MilestoneSampler + rewritten readSampledUserTurns)
  are all in place; downstream consumer (LLMPrompts.titleInput) still uses
  the v0.2.7 inline keyword filter. That consumer refactor is Phase 5.
