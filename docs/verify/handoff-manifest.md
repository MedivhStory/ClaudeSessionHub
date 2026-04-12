# Verification Handoff: Phase 7 — Build plugin + PromptBuilderHasher

**Branch:** feature/v0.2.8-ai-eval
**Commit SHA:** a16123acdbec7c4707315b80d6f7a49a9402bc26
**Handoff time:** 2026-04-12T13:30:07Z
**Phase:** 7 — Build plugin + PromptBuilderHasher (🛑 second verify checkpoint)

## 1a. What changed

### Affected components
- `Sources/ExtractPromptSourceTool/main.swift` (new — Phase 7.1)
- `Plugins/ExtractPromptSource/Plugin.swift` (new — Phase 7.2)
- `Sources/EvalHarnessCore/PromptBuilderHasher.swift` (new — Phase 7.3)
- `Package.swift` (modified: +ExtractPromptSourceTool exe target, +ExtractPromptSourcePlugin, +ExtractPromptSourceToolTests, EvalHarnessCore plugin attachment)
- `Tests/ExtractPromptSourceToolTests/ExtractionTests.swift` (new, 4 tests)
- `Tests/EvalHarnessTests/PromptBuilderHasherTests.swift` (new, 4 tests)

(Plus all Phase 1-6 components from previous checkpoint)

### Spec references
- Implements: §2.5 (promptBuilderHash precise definition), §6.2 (Package.swift plugin architecture), I-5 (hash contract: extraction failure → build failure → no binary → no tag)

### Change description
- New `ExtractPromptSourceTool`: standalone executable that reads `LLMPrompts.swift`, locates `public static func titleInput(` via brace-matching, extracts function body, writes `GeneratedPromptSource.swift`. Hard-fails with exit codes 2-5 on any extraction failure.
- New `ExtractPromptSourcePlugin`: SwiftPM build tool plugin that wires the tool into EvalHarnessCore build. Plugin outputs to `context.pluginWorkDirectory`. Generated source auto-linked into `EvalHarnessCore` at compile time.
- New `PromptBuilderHasher`: computes SHA256 over canonical blob of 4 prompt assets (3 system prompts + titleInput function source). Used by release gate to detect prompt drift.

### Scenarios
- `docs/verify/scenarios/004-sampling-library-complete.md` (previous checkpoint)
- `docs/verify/scenarios/007-build-plugin-hasher.md` (this checkpoint)

## 1b. Environment requirements

### LLM mode
- `disabled` — this checkpoint exercises only build pipeline and hash computation. No LLM invocation.

### Required environment variables
- none

### Network
- `offline OK`

### Xcode version
- Xcode 26.4 or newer (baseline)

### MCP availability assumptions
- none beyond baseline

### Pre-flight installs
- none

### macOS permission requirements
- none beyond macos-automator baseline
- Note: SwiftPM build plugin trust was auto-approved on this machine (no dialog appeared). If running on a fresh machine, macOS may prompt "Allow plugin to run?" on first `swift build`.

## Notes for verifier
- `GeneratedPromptSource.swift` is NOT in the source tree. It lives in `.build/plugins/outputs/`. Do not look for it under `Sources/`.
- PromptBuilderHasher reads 3 runtime string constants from `LLMPrompts` + 1 build-time captured source from `GeneratedPromptSource`. All 4 are present after a successful `swift build`.
- Full test suite: 275 tests, 0 failures. Baseline before v0.2.8 was 165. Delta +110 through Phase 7.
- Phase 8 (FixtureLoader + Verifier + PreCheck) is gated on this checkpoint's approval.

## Commit range (Phase 7 only)
```
1c391c8 feat(build): ExtractPromptSourceTool with hard-fail extraction
9d4cc87 feat(build): ExtractPromptSourcePlugin wires tool into EvalHarnessCore
a16123a feat(harness): PromptBuilderHasher computes SHA256 over 4 prompt assets
```
