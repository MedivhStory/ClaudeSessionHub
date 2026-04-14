# Release Gate Process

Every release tag must be preceded by a passing live eval gate run. The
invariant is: **no pass, no tag.**

The steps below must be executed in order. Do not skip or reorder them.

---

## Command sequence

### Step 1 — Ensure all tests pass

```bash
swift test
```

All unit tests must pass before the live eval gate is run. A failing test suite
invalidates the gate result.

### Step 2 — Run the release gate

```bash
swift run eval-harness live \
  --release \
  --tag v0.2.8 \
  --fixtures Tests/Fixtures/eval
```

The `--release` flag causes the harness to write a signed artifact file to
`docs/eval/gate-runs/`. The artifact encodes the binding fields listed in the
next section. The command exits non-zero if any fixture fails.

### Step 3 — Commit the artifact

```bash
git add docs/eval/gate-runs/<artifact>.json
git commit -m "chore(eval): v0.2.8 release gate artifact"
```

Replace `<artifact>.json` with the filename printed by the harness in step 2.
Only the artifact file should be staged in this commit.

### Step 4 — Verify the artifact

```bash
swift run eval-harness check-artifact --tag v0.2.8
```

The `check-artifact` subcommand:

1. Locates the artifact file for `v0.2.8` under `docs/eval/gate-runs/`.
2. Verifies that exactly one artifact exists for that tag (see uniqueness rule below).
3. Checks all eight binding fields against the current build environment.

The command exits non-zero if any check fails. Do not proceed to step 5 if
this command fails.

### Step 5 — Apply the tag

```bash
git tag -a v0.2.8 -m "v0.2.8 — AI Quality Infrastructure"
```

### Step 6 — Push

```bash
git push origin main --tags
```

---

## Artifact binding fields

A release artifact is considered valid only when all eight binding fields match:

| Field | Description |
|---|---|
| `mode` | Must be `"release"`. Dev-mode artifacts are not accepted. |
| `commitSHA` | The git commit SHA at the time of the gate run. |
| `promptBuilderHash` | SHA-256 of the prompt builder source at that commit. |
| `dslSchemaVersion` | The DSL schema version used to evaluate fixtures (currently `"1"`). |
| `provider` | The inference provider (canonical: `"DashScope"`). |
| `model` | The model identifier (canonical: `"qwen-plus"`). |
| `temperature` | Sampling temperature (canonical: `0`). |
| `gateResult` | Must be `"pass"`. |

If any field differs between the artifact and the current build, `check-artifact`
fails and the tag must not be applied until a new gate run produces a matching
artifact.

---

## Canonical provider configuration

For release gate runs the following inference configuration must be used:

- **Provider:** DashScope
- **Model:** `qwen-plus`
- **Temperature:** `0`

Using a different provider, model, or temperature produces an artifact that will
not satisfy the binding check against the canonical values.

---

## Invariants

### No pass, no tag

A release tag must not be applied unless `check-artifact` exits with status 0
for that tag. This rule is not advisory; it is a hard process invariant.

### Unique match rule

Exactly one artifact must exist for a given tag. If `check-artifact` finds zero
or more than one artifact for the requested tag it exits non-zero. If a gate run
must be repeated (e.g. after a fix), delete the previous artifact before
committing the new one so that only one artifact exists per tag at commit time.
