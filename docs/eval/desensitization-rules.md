# Desensitization Rules

Real-snapshot fixtures (`"kind": "real-snapshot"`) are created from production
session data. Before a snapshot may be committed to the repository it must be
desensitized according to the rules in this document.

Desensitization must preserve the structural and semantic properties that the
eval harness tests; it must not sanitize signals or distort relationships that
the model is expected to reason about.

---

## Hard rules

### Rule 1 — Scope: sensitive identifiers only

Desensitize sensitive identifiers. Do not desensitize or alter structural
signals. The harness tests AI reasoning over structure; removing or obscuring
structural features invalidates the fixture.

### Rule 2 — Preserve structural properties

The following must be preserved exactly:

- **Time order** — turns and events must appear in the same chronological order
  as the original.
- **Turn count magnitude** — the total number of turns must not change. Do not
  collapse, merge, or add turns.
- **Version number positions** — if a version string appears at turn N in the
  original, it must appear at turn N in the desensitized snapshot.
- **Milestone distribution** — the relative position of milestones within the
  session (e.g. first mention of a goal, first passing test) must be preserved.
- **`rawTurns` semantic relationships** — if turn B references or builds on turn
  A in the original, that dependency must remain recognisable in the desensitized
  form.

### Rule 3 — Replace sensitive identifiers

The following categories must be replaced:

- Usernames and personal identifiers
- Absolute file-system paths
- Repository names and organisation names
- Tokens, API keys, secrets, and credentials
- Internal domain names and hostnames

Replacements should be plausible stand-ins (e.g. `username` → `alice`,
`/Users/jsmith/Projects/foo` → `/Users/alice/Projects/bar`) rather than
obvious placeholders (`REDACTED`, `XXX`). Plausible replacements reduce the
risk of the model producing artifacts that pattern-match against placeholder
strings.

### Rule 4 — Timestamps

- A uniform time shift (adding or subtracting a fixed offset from every
  timestamp) is permitted provided it preserves all deltas (Δt).
- Timestamps must never be reordered.
- Timestamps must never be rescaled (i.e. compressing or expanding the
  intervals between events is not allowed).

### Rule 5 — Version strings

- Public semver strings must preserve shape and punctuation
  (e.g. `1.4.2` may become `2.1.0` but not `v2-1-0` or `"two point one"`).
- If the product name in a version string is sensitive, rename the product but
  keep the version token in its original form
  (e.g. `InternalTool 3.2.1` → `PublicTool 3.2.1`).

---

## Pilot exit criteria

Before a new real-snapshot fixture class is promoted to the standard fixture
suite, the following criterion must be met:

**N=2 different failure modes must reproduce on desensitized snapshots.**

That is: for at least two distinct `meta.failureMode` values, the desensitized
fixture must cause the same model behaviour (pass or fail) as the original
production capture.

This criterion guards against over-desensitization that accidentally removes
the signal responsible for the regression being captured.

---

## Pre-check script

Use the pre-check script to verify a desensitized snapshot before committing:

```bash
swift scripts/eval/precheck_desensitization.swift \
  --raw      <path-to-original-session.json> \
  --snapshot <path-to-desensitized-snapshot.json>
```

The script checks Rules 1–5 mechanically where possible and prints a
PASS / FAIL summary with per-rule details. Fix all FAILs before committing
the snapshot.

---

## Evolution rules

- The pre-check verifier (`scripts/eval/precheck_desensitization.swift`) is
  independently maintained.
- **The verifier cannot be modified in the same PR as product extractor code.**
  Changes to the verifier require a separate PR with a dedicated review.
- This constraint ensures the verifier remains an independent check on the
  extractor rather than being updated to paper over extractor regressions.
