# Scenario: complete fixture set (Phase 10 checkpoint)

## Steps
1. Run: `swift run eval-harness validate-fixtures --fixtures Tests/Fixtures/eval`
   Expected: "✓ 6 fixtures validated; no errors"
2. Run: `ls Tests/Fixtures/eval/*.input.json Tests/Fixtures/eval/*.expected.json | wc -l`
   Expected: 12 (6 pairs)
3. Confirm 5-pattern PII scan clean on both real-snapshot files:
   `for p in medivh_openclaw medivh-openclaw /Users/medivh MedivhStory medivh-openclawtekiMac-mini.local; do grep -c "$p" Tests/Fixtures/eval/real-snapshot-0{1,2}.input.json; done`
   Expected: all zero
4. Confirm session-1 failureMode is "mixed-context-sanity":
   `python3 -c "import json; print(json.load(open('Tests/Fixtures/eval/real-snapshot-01.input.json'))['meta']['failureMode'])"`
   Expected: "mixed-context-sanity"
5. Confirm session-2 requires v0.2.x in title+summary:
   `python3 -c "import json; e=json.load(open('Tests/Fixtures/eval/real-snapshot-02.expected.json')); print(e['title']['mustContainAny'], e['summary']['mustContainAny'])"`
   Expected: ['0.2'] ['0.2']
6. Run: `swift test 2>&1 | grep 'Executed [0-9]\{3\} tests' | tail -2`
   Expected: 339 tests, 0 failures (unchanged from baseline)

## Expected
- 6 fixtures validate cleanly (4 synthetic + 2 real-snapshot)
- No PII residue on any of the 5 patterns in either real-snapshot
- Pilot exit criteria (I-10) satisfied: N=2 real snapshots from 2 different sessions
- DesensitizeSession tool functional (used to produce both snapshots)
- precheck_desensitization structural fidelity reports clean for both

## Notes
- Mapping tables live at /tmp/cshub-mapping/session-{1,2}/ (local, never committed)
- Session-1 is a MIXED-CONTEXT-SANITY fixture, NOT a failure-mode reproducer (the session is literally the v0.2.8 eval harness dev session itself)
- Session-2 is a subtopic-bias+cross-version-drift fixture requiring 0.2 in title+summary
- The 4 synthetic fixtures still pass 3/4 in dev-mode live eval (version-hallucination summary leak is genuine quality signal, fail-closed under locked spec)
- Phase 12 full release gate NOT yet run
