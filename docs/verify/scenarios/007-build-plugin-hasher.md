# Scenario: build plugin + PromptBuilderHasher (Phase 7 checkpoint)

## Steps
1. Run: `swift build 2>&1 | grep -i "extracting\|GeneratedPromptSource"`
   Expected: see "Extracting LLMPrompts.titleInput source" and "Compiling ... GeneratedPromptSource.swift"
2. Run: `find .build -name "GeneratedPromptSource.swift" | head -1`
   Expected: one file in `.build/plugins/outputs/.../ExtractPromptSourcePlugin/`
3. Run: `swift test --filter PromptBuilderHasherTests`
   Expected: 4/4 passing (hash prefix, stability, all 4 sections, generated source content)
4. Run: `swift test --filter ExtractionTests`
   Expected: 4/4 passing (valid function, missing file, missing function, real LLMPrompts.swift)
5. Run: `swift test 2>&1 | grep "Executed.*tests" | tail -2`
   Expected: 275 tests, 0 failures
6. Confirm: generated file contains "MilestoneSampler" (evidence that titleInput body was captured)
   `cat $(find .build -name "GeneratedPromptSource.swift" | head -1) | grep -c MilestoneSampler`
   Expected: ≥ 1

## Expected
- Plugin fires during build and produces GeneratedPromptSource.swift in plugin work directory
- Tool hard-fails on invalid input (exit codes 2-5 per spec)
- PromptBuilderHasher.currentHash() returns stable "sha256:..." prefix
- PromptBuilderHasher.canonicalBlob() contains all 4 labeled sections
- No macOS plugin trust prompt (already auto-trusted on this machine)
- Full test suite 275 tests green

## Notes
- This is the second verify checkpoint. Plugin pipeline + hash contract (I-5) are now wired.
- The generated file is NOT in the source tree. It lives only in `.build/plugins/outputs/`.
- If the tool extraction logic breaks (e.g., someone renames titleInput), the build fails immediately — this is by design (I-5).
