# Changelog

## [v0.2.8.3] - 2026-04-20

### Added
- Menu-bar "AI > 批量 AI 增强全部会话" command (⇧⌘E) for all visible non-archived sessions

### Changed
- Expanded English verb pattern from 16 to 60+ imperatives to reduce UUID fallback titles (partial fix — 10+50 entry window limitation still exists, deeper fix deferred)

### Removed
- `extractKeyTurns` public method (zero callers since v0.2.8.1, replaced by `extractEnhanceInputs`)
- Dead `formatTokenCount` and `contextBarColor` from QuickFactsView

---

## [v0.2.8.2] - 2026-04-17

### Added
- About window with version, author, GitHub link, MIT license (`AppVersion.swift` as single version source)

### Fixed
- Token count showed 0 — `extractContextUsage` now skips `<synthetic>` sentinel entries with all-zero tokens
- AI enhance unreachable by VoiceOver — added `.accessibilityAction` for tile expand/collapse and button labels
- 5 section headings had no a11y labels — added `.isHeader` trait to AI 理解, Attention Inbox, Active Sessions, Project Portfolio, Recently Finished
- AI config lost on restart — `SettingsStore.init()` now loads API key eagerly instead of deferring

### Changed
- README: removed `~/.claude/` sub-path enumeration from Data Sources section
- README: test badge uses "passing" instead of hardcoded counts; API key limitation updated

---

## [v0.2.8.1] - 2026-04-16

### Fixed
- `firstUserIntent` / `lastUserIntent` recovery when real text is outside the 10+50 window
- `historyDisplayTexts` fallback from JSONL when `history.jsonl` has no rows
- `rawTurns` position-labelled with [首]/[中]/[末] markers
- `SignalExtractor.enrich` preserves JSONL-derived history instead of wiping it
- Dual-build test coverage added for all five `extractEnhanceInputs` fixes

---

## [v0.2.8] - 2026-04-15

### Added
- Eval harness CLI (`eval-harness`) for automated prompt quality evaluation
- Release gate with fail-closed semantics and 8-way binding
- Gate artifacts in `docs/eval/gate-runs/` (immutable audit history)
- VersionMention model and VersionMentionExtractor for structured version extraction
- MilestoneSampler for time-distributed + version-density history sampling
- ExtractPromptSourcePlugin build plugin for prompt template hash binding
- DesensitizeSession CLI for creating eval fixtures from real sessions

### Changed
- Prompt system improvements for title/progress/summary generation
- `SessionSignals` extended with `versionMentions`, `totalEntryCount`, `slashCommands`, `commandErrors`

---

## [v0.2.7] - 2026-04-10

### Security
- **API key moved out of `settings.json` into a separate secret file** (`~/.claude-hub/.apiKey.secret`, plaintext with `0600` permissions, parent dir `0700`) — protects against accidental sharing of `settings.json`, not against local disk access
- SecretStore protocol with FileSecretStore (production, atomic write with 0600) + InMemorySecretStore (tests, NSLock)
- Automatic migration: legacy plaintext key in `settings.json` → secret file on first use
- Lazy key loading: secret file only accessed when AI features are triggered, not at app startup or when Settings opens
- TextField replaces SecureField to avoid macOS Passwords autofill trigger on unsigned apps
- Note: Keychain was evaluated and rejected — it prompts permission dialogs for unsigned dev builds. Keychain migration is deferred to post-signing.

### Added
- **Batch enhance progress indicator**: `3/10 增强中...` with ProgressView in list header
- `@MainActor` on `historyTextsCache` (Sendable safety)
- `Date.relativeFormatted` extension (replaces duplicated helper in 2 views)

### Fixed
- Settings UI: "已保存" text clears on provider switch
- Settings UI: API Key placeholder only shows "留空则保留" for matching provider
- Settings UI: shared config builder for save + test (consistent trimming)
- Settings UI: model picker "其他..." option hides TextField when standard model selected
- Test connection loads saved key when user didn't type a new one
- Batch enhance calls `ensureApiKeyLoaded` before `isConfigured` check
- FileSecretStore: atomic file creation with 0600 (no race window)
- InMemorySecretStore: thread-safe via NSLock
- Directory permissions set to 0700
- Cached `RelativeDateTimeFormatter` (static let)
- UI test: updated assertions for QuickFacts changes (context/stats moved to collapsed tile)

---

## [v0.2.6] - 2026-04-09

### Added — LLM Provider Presets
- **Provider picker**: OpenAI, 阿里云百炼 (3 regions), DeepSeek, Moonshot, Ollama, Custom
- **Auto-fill**: Select provider → endpoint + suggested models auto-populated
- **Smart endpoint**: Auto-appends `/chat/completions` to base URLs
- **Ollama support**: No API key required for local models
- **Model suggestions**: Per-provider recommended model names
- **Backward compatibility**: v0.2.5 configs without `provider` field auto-default to Custom

### Fixed
- `rawTurns.prefix(3)` bug: prompt builder no longer re-truncates upstream-sampled turns
- Milestone-priority history sampling for version-aware prompts
- LLMProvider raw values changed to stable machine keys (not Chinese display strings)

---

## [v0.2.5] - 2026-04-08

### Added — LLM Enhancement Layer
- **Optional AI-powered understanding**: Connect any OpenAI-compatible API for AI titles, progress summaries, and session overviews
- **LLMUnderstandingSnapshot**: Complete AI understanding result per session (title + progress + summary + metadata)
- **UnderstandingStore**: Independent persistence (`~/.claude-hub/understanding.json`), fully separated from rule-based TitleStore
- **LLMEnhancer**: Standalone service consuming structured SessionSignals, not raw JSONL
- **LLMClient**: Pure URLSession HTTP client for OpenAI-compatible chat completions
- **LLMPrompts**: Prompt templates with session scale awareness for long sessions
- **LLMConfig**: API endpoint, key, model configuration in Settings
- **Stale detection**: `basedOnLastActiveAt` field tracks when AI understanding was generated relative to session activity
- **Settings UI**: AI Enhancement section with endpoint/key/model fields, test connection button

### Added — UI Redesign
- **Elastic collapsed tiles**: 2 lines for healthy sessions, 3 lines with health signals
- **Two-column expanded view**: Left (rule/facts/operations) + Right (AI understanding panel)
- **LLMPanelView**: 4-state right panel (fresh snapshot, stale, configured-no-snapshot, unconfigured)
- **Session stats in collapsed tile**: Created date, turn count, context usage bar moved from expanded to collapsed right side
- **Source badge**: "AI" (purple) or "规则" (gray) after title
- **Batch AI enhance**: Button in list header, scoped to visible sessions
- **Per-session regenerate**: Always available in expanded AI panel

### Changed
- **Font sizes increased**: Title 16pt, summary 13pt, metadata 12pt, labels 11pt
- **Context progress bar**: Constrained to 50pt width, inline with stats
- **Action buttons**: Refresh and resume moved to title row right end

### Fixed
- `extractSignals` performance: Line counting instead of full JSON parse for `totalEntryCount`
- `extractKeyTurns` performance: Head+middle+tail sampling instead of full file read
- `batchEnhanceLLM` now refreshes stale snapshots, not just missing ones
- `LLMConfig.isConfigured` requires `modelName` (prevents silent 400 errors)
- Dead code removed from QuickFactsView (75 lines)
- Test button disabled when model name is empty

---

## [v0.2.0] - 2026-04-07

### Added — Understanding Layer
- **Smart session naming**: Rule-based title generation from history.jsonl, tasks/, and JSONL signals
- **Title normalization pipeline**: Strips pasted wrappers, URLs, file paths, terminal prompt chars, XML tags, shell commands
- **Last progress extraction**: Completion-oriented language matching ("完成/done/fixed/implemented")
- **Placeholder titles**: Descriptive placeholders for command-only sessions (e.g. "恢复会话失败", "登录中断")
- **Title evolution**: Manually triggerable refresh, history preserved, dedup on same content
- **SessionSignals model**: Structured signal extraction from all data sources
- **SignalExtractor**: Reads history.jsonl + tasks/ as enrichment sources
- **SessionTitleStrategy protocol**: Rule-based implementation with LLM slot reserved
- **TitleStore**: Persists titles, progress, user notes to `~/.claude-hub/titles.json`
- **User notes**: Right-click context menu to add manual annotations

### Added — Search & Relations
- **Weighted content-first search**: Scores across smart title, notes, history, tasks, branch, progress
- **Search evidence**: Purple inline snippets showing why a session matched
- **Session relationships**: Same-branch and time-continuation detection

### Added — Data & Infrastructure
- **Data directory hot-switch**: Changes take effect without restart
- **Path normalization**: `~/.claude` expansion, whitespace trimming
- **UI test isolation**: `--ui-test-mode` uses temp directory for all stores
- **HeatStrip accessibility**: Replaced onTapGesture with Button for reliable XCUITest

### Fixed
- SettingsStore auto-save via explicit setter methods (works with @Observable)
- ScanTimerModifier: Timer.scheduledTimer replaced with .task (no leak)
- @unchecked Sendable safety comments on ClaudeProvider, LabelStore, ArchiveStore
- lastActiveAt: Scans backward for first entry with valid timestamp (fixes false-stale)

---

## [v0.1.1] - 2026-04-01

### Initial Release
- Native macOS SwiftUI application for Claude Code session management
- Project → Session hierarchy with sectioned sidebar
- 3-layer session tiles with health signals
- Overview dashboard with summary cards, heat strip, attention inbox
- One-click resume in Ghostty or Terminal.app
- Session archiving and manual labels
- 56 unit tests + 16 UI tests
- Provider abstraction (Claude Code + Codex stub)
