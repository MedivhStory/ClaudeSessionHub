[English](./README.md) | [简体中文](./README.zh-CN.md)

<div align="center">

<img src="Resources/AppIcon.png" width="128" height="128" alt="Claude Session Hub Icon">

# Claude Session Hub

**A native macOS task manager for Claude Code sessions.**

Discover, organize, and understand your sessions across all projects — at a glance.

*Enjoy AI, but don't forget to govern it.*

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Tests](https://img.shields.io/badge/Tests-142%20unit%20%2B%2016%20UI-brightgreen)](.)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](LICENSE)

</div>

---

## Install

1. Download **[ClaudeSessionHub.dmg](https://github.com/MedivhStory/ClaudeSessionHub/releases/latest)** from Releases
2. Open the DMG
3. Drag **ClaudeSessionHub** to **Applications**
4. Launch from Applications

### First launch

macOS may block the app because it isn't signed with a Developer ID:

- **Right-click** the app > select **Open** > click **Open** in the dialog.

If that doesn't work:

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeSessionHub.app
```

---

## What It Does

Claude Session Hub reads your local Claude Code data (`~/.claude/`) and gives you a unified dashboard to manage all your sessions. Fully offline by default, with optional AI enhancement.

### Core Features

- **Smart Session Naming** — Rule-based title generation from history.jsonl, tasks, and JSONL signals. Automatically cleans up command noise, pasted wrappers, file paths.
- **Last Progress Tracking** — Answers "what was recently completed?" not "what was last said". Filters noise from permissions, resume, and system messages.
- **Optional AI Enhancement** — Connect any OpenAI-compatible API to get AI-powered titles, progress summaries, and session overviews. Works with GPT-4o, Claude, or any compatible endpoint.
- **Two-Column Expanded View** — Left: rule-based facts, files, operations. Right: AI understanding panel with title, progress, and summary.
- **Elastic Collapsed Tiles** — 2 lines for healthy sessions, 3 lines when health signals need attention.
- **Content-First Search** — Weighted scoring across smart titles, notes, history, tasks, branch, and progress. Match evidence shown inline.
- **Session Relationships** — Detect same-branch and time-continuation relationships across sessions.
- **Health Signals** — Stale sessions, context near full, recent errors — surfaced only when relevant.
- **One-Click Resume** — Resume any session in Ghostty or Terminal.app.

### AI Enhancement (Optional)

Configure in Settings > AI Enhancement:

1. Enter your OpenAI-compatible API endpoint
2. Add your API key and model name
3. Click "Test Connection" to verify

Once configured:
- Expand any session > click **"Generate AI Understanding"** in the right panel
- Or use **"Batch AI Enhance"** in the list header for visible sessions
- AI results are cached and marked stale when sessions update
- Everything works without AI — rule-based understanding is always available

## Requirements

- **macOS 14** (Sonoma) or later
- Claude Code installed (`~/.claude/` data directory)

## Architecture

```
SessionStore (@Observable, @MainActor)
  ├─ ScanCoordinator (actor)
  │    └─ ClaudeProvider (dynamic directory)
  │
  │  Rule Layer (auto, every scan)
  ├─ RuleTitleStrategy → TitleStore (titles.json)
  │    └─ Smart titles, progress, placeholders
  │
  │  LLM Layer (manual trigger only)
  ├─ LLMEnhancer → UnderstandingStore (understanding.json)
  │    └─ AI titles, progress, summaries
  │
  ├─ SignalExtractor (history.jsonl + tasks/)
  ├─ LLMClient (OpenAI-compatible HTTP)
  └─ SettingsStore (settings.json + LLMConfig)
```

**Data sources** (read-only, never modified):

| Source | Path | Purpose |
|---|---|---|
| Session JSONL | `~/.claude/projects/<key>/<id>.jsonl` | Session content |
| Process metadata | `~/.claude/sessions/<pid>.json` | PID liveness |
| History index | `~/.claude/history.jsonl` | User commands |
| Tasks | `~/.claude/tasks/<id>/*.json` | Structured goals |

App settings stored in `~/.claude-hub/`.

## Current Limitations

- Codex provider is a stub (protocol ready, no implementation)
- Not code-signed or notarized (first launch requires right-click > Open)
- AI prompt language is Chinese — may produce suboptimal results with English-only models
- API key stored in plaintext in settings.json (Keychain migration planned)

## Development

<details>
<summary>For contributors and developers</summary>

```bash
# Run from source
swift run ClaudeSessionHub

# Run from Xcode
# Open Package.swift > select ClaudeSessionHub scheme > Cmd+R

# Unit tests (142)
swift test

# Xcode unit tests (83)
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -scheme ClaudeSessionHub \
  -destination 'platform=macOS' \
  test -only-testing:'ClaudeSessionHubTests'

# UI tests (16, requires Xcode)
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -scheme ClaudeSessionHub \
  -destination 'platform=macOS' \
  test -only-testing:'ClaudeSessionHubUITests'

# Build .app
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -target ClaudeSessionHub \
  -configuration Release \
  build CODE_SIGNING_ALLOWED=NO CONFIGURATION_BUILD_DIR=./dist
```

</details>

## License

MIT — see [LICENSE](LICENSE) for the full text.

**MIT, in human words:** use it, ship it, remix it, break it, fix it — just keep the copyright notice and don't blame the author if it catches fire.

> *Friendly summary only. See [LICENSE](LICENSE) for the actual terms.*

---

<div align="center">

*Enjoy AI, but don't forget to govern it.*

Built with SwiftUI. Designed for Claude Code power users.

</div>
