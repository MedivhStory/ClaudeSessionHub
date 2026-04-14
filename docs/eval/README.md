# Eval Harness

The eval harness is a two-layer quality gate for LLM-enhanced session understanding
in ClaudeSessionHub. It verifies that the AI inference pipeline (prompt construction,
model invocation, response parsing) produces results that satisfy a declarative set of
constraints defined in fixture files — both during local development and as a mandatory
pre-tag release gate.

## What it is

The harness consists of two layers:

1. **Fixture validation** — structural and semantic checks run offline against
   `*.input.json` / `*.expected.json` fixture pairs. No model calls are made.
2. **Live evaluation** — real model calls are made for every fixture; each response
   is scored against the DSL constraints in the corresponding `*.expected.json`.

Both layers must pass before a release tag is applied. See `release-gate-process.md`
for the full command sequence.

## Subcommands

### `validate-fixtures`

Validates all fixture pairs under a directory for schema conformance and DSL
operator correctness. No model calls are made.

```bash
swift run eval-harness validate-fixtures --fixtures Tests/Fixtures/eval
```

### `live`

Runs live model calls for every fixture and scores responses against their
expected constraints. In `--release` mode the result is written as a signed
artifact under `docs/eval/gate-runs/`.

```bash
# Development run (no artifact written)
swift run eval-harness live --fixtures Tests/Fixtures/eval

# Release gate run (artifact written, tag recorded)
swift run eval-harness live --release --tag v0.2.8 --fixtures Tests/Fixtures/eval
```

### `check-artifact`

Verifies that a committed release artifact for a given tag exists and is
internally consistent (binding fields match the current build). Must pass
before `git tag` is applied.

```bash
swift run eval-harness check-artifact --tag v0.2.8
```

## Quick start

```bash
# 1. Validate fixture files only (fast, no model calls)
swift run eval-harness validate-fixtures --fixtures Tests/Fixtures/eval

# 2. Run a live development pass
swift run eval-harness live --fixtures Tests/Fixtures/eval

# 3. Full release gate sequence — see release-gate-process.md
swift test
swift run eval-harness live --release --tag v0.2.8 --fixtures Tests/Fixtures/eval
git add docs/eval/gate-runs/<artifact>.json
git commit -m "chore(eval): v0.2.8 release gate artifact"
swift run eval-harness check-artifact --tag v0.2.8
git tag -a v0.2.8 -m "v0.2.8 — AI Quality Infrastructure"
git push origin main --tags
```

## Further reading

| File | Contents |
|---|---|
| `fixture-schema.md` | Full schema reference for `*.input.json` and `*.expected.json` |
| `desensitization-rules.md` | Rules for creating real-snapshot fixtures from production data |
| `release-gate-process.md` | Step-by-step pre-tag release gate procedure and artifact binding rules |
