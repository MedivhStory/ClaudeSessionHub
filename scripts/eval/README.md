# scripts/eval — Desensitization Tooling

Operator tools for creating real-snapshot eval fixtures from live Claude Code session files.

---

## DesensitizeSession

An internal executable that reads a raw Claude Code session JSONL, applies text replacements
from mapping CSV files, and emits a `*.input.json` fixture file conforming to `FixtureInputFile`
schema (schemaVersion `"1"`, kind `real-snapshot`).

### Invocation

```bash
swift run DesensitizeSession \
  --input    /path/to/session.jsonl \
  --mapping  /path/to/mapping-dir/ \
  --output   Tests/XCTests/Fixtures/my-fixture.input.json \
  --id       my-fixture \
  --failure-mode version-hallucination \
  --description "Real session where model invented a version number"
```

| Flag | Required | Description |
|---|---|---|
| `--input` | yes | Path to the raw `.jsonl` session file |
| `--mapping` | yes | Directory containing mapping CSV files |
| `--output` | yes | Destination path for the generated `.input.json` |
| `--id` | yes | Fixture identifier (used in `id` field and as session ID fallback) |
| `--failure-mode` | no | Failure mode tag (e.g. `version-hallucination`). Pass `none` to omit. |
| `--description` | yes | Human-readable description of the fixture scenario |

Progress lines are printed to **stderr**; the output JSON is written to `--output`.

---

## precheck_desensitization

A standalone Swift script (Foundation only, **no project imports**) that performs a structural
fidelity check between a raw JSONL and the desensitized snapshot JSON.

It checks:
- User-turn counts match (raw vs `signals.turnCount`)
- `historyDisplayTexts` and `rawTurns` are populated
- Version-mention extraction is consistent
- Milestone keywords (`版本`, `封版`, `release`, `tag`, `milestone`) present in raw are
  represented in the snapshot

### Invocation

```bash
swift scripts/eval/precheck_desensitization.swift \
  --raw      /path/to/session.jsonl \
  --snapshot Tests/XCTests/Fixtures/my-fixture.input.json
```

The script prints a comparison table to stdout and exits 0. Discrepancies are flagged with
`WARN` / `INFO` labels — review them manually before committing the fixture.

---

## Mapping CSV format

Each mapping directory passed to `--mapping` may contain up to three CSV files:

| File | Purpose |
|---|---|
| `usernames.csv` | Replace real usernames / display names |
| `paths.csv` | Replace real filesystem paths |
| `repos.csv` | Replace real repository names / URLs |

Each file uses one `original,replacement` entry per line:

```
john.doe,REDACTED_USER
/Users/john.doe/work,/Users/OPERATOR/work
acme-internal-repo,example-repo
```

Rules:
- Lines starting with `#` and blank lines are ignored.
- Replacements are applied longest-first to avoid partial shadowing.
- All three files are optional; missing files are skipped with a warning.

### IMPORTANT: Mapping tables MUST NOT be committed to git

Mapping CSVs contain real usernames, paths, and repository names. They must **never** be
added to version control. Add your mapping directory to `.gitignore`:

```
# Desensitization mappings — NEVER commit
mappings/
```
