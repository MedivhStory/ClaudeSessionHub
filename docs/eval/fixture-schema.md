# Fixture Schema Reference

Each fixture consists of two files that share the same base name:

- `<id>.input.json` — signals and raw turns fed to the prompt builder
- `<id>.expected.json` — DSL constraints the model response must satisfy

Both files carry `schemaVersion: "1"`.

---

## `*.input.json`

```jsonc
{
  "schemaVersion": "1",
  "id": "unique-fixture-id",
  "kind": "synthetic" | "real-snapshot",
  "meta": {
    "failureMode": "string — short label for the regression this fixture guards",
    "description": "string — human-readable explanation",

    // real-snapshot only:
    "desensitizedAt": "ISO-8601 timestamp",
    "desensitizationScriptVersion": "semver string"
  },
  "input": {
    "signals": {
      // Structured signals derived from the session.
      // Keys are defined by the extractor; values are strings, numbers, or arrays.
    },
    "rawTurns": [
      // Array of turn objects: { "role": "user"|"assistant", "content": "string" }
    ],
    "basedOnLastActiveAt": "ISO-8601 timestamp"
  }
}
```

### Field notes

- `kind`: `"synthetic"` fixtures are hand-authored; `"real-snapshot"` fixtures are
  desensitized captures of real sessions (see `desensitization-rules.md`).
- `meta.failureMode`: used in harness output and artifact summaries to identify
  which regression a failing fixture corresponds to.
- `input.signals`: the harness passes this object verbatim to the prompt builder.
- `input.rawTurns`: passed verbatim. Order is preserved; the harness does not sort
  or deduplicate.
- `input.basedOnLastActiveAt`: anchors any relative-time reasoning in the prompt.

---

## `*.expected.json`

```jsonc
{
  "schemaVersion": "1",
  "id": "must match the id in the corresponding *.input.json",

  // All three output fields are optional.
  // Omitting a field means "no constraint on this field".
  "title":    { /* FieldConstraint — see DSL operators below */ },
  "progress": { /* FieldConstraint — see DSL operators below */ },
  "summary":  { /* FieldConstraint — see DSL operators below */ },

  // Optional. Required only when a mustContainAny / mustContainAll operator
  // is non-obvious or context-dependent; explains why those strings are correct.
  "verbatimMatchJustification": "string"
}
```

### FieldConstraint

A `FieldConstraint` is a JSON object that may contain any combination of the
operators below. All present operators must pass for the field to pass.

---

## DSL Operators

See spec §2.3 for the authoritative operator specification.

| Operator | Value type | Description |
|---|---|---|
| `mustContainAny` | `string[]` | The field value must contain at least one of the listed substrings (case-sensitive). |
| `mustContainAll` | `string[]` | The field value must contain every listed substring (case-sensitive). |
| `mustNotContain` | `string[]` | The field value must not contain any of the listed substrings (case-sensitive). |
| `mustNotEqual` | `string` | The field value must not be exactly equal to this string. |
| `mustNotBeEmpty` | `boolean` | When `true`, the field value must be a non-empty string. |
| `minLength` | `number` | The field value must have at least this many characters. |
| `maxLength` | `number` | The field value must have at most this many characters. |
| `mustMatchRegex` | `string` | The field value must match this regular expression (ICU syntax). |
| `maxRegexMatchCount` | `{ "pattern": string, "max": number }` | The number of non-overlapping matches of `pattern` in the field value must not exceed `max`. Useful for bounding repetition. |

### Operator evaluation

- All operators within a `FieldConstraint` are evaluated with AND semantics.
- Array operators (`mustContainAny`, `mustContainAll`, `mustNotContain`) apply to
  the string value of the field, not to array elements.
- An empty array for `mustContainAny` or `mustContainAll` always passes vacuously.
- Unknown operator keys cause the harness to fail-closed with a schema error.

---

## Schema version evolution policy

- The current version is `"1"`. The version string is a bare integer in quotes.
- When the schema changes in a breaking or additive way, the version is bumped.
- There is no automatic migration between versions. Old fixtures must be updated
  manually when a new version is adopted.
- The harness fails-closed on an unknown `schemaVersion`: it will not attempt to
  process a fixture whose version it does not recognise.
- A new version requires a corresponding update to this document.
