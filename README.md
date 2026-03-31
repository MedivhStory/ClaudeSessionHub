[English](./README.md) | [简体中文](./README.zh-CN.md)

<div align="center">

<img src="Resources/AppIcon.png" width="128" height="128" alt="Claude Session Hub Icon">

# Claude Session Hub

**A native macOS task manager for Claude Code sessions.**

Discover, organize, and surface session health across all your projects — at a glance.

*Enjoy AI, but don't forget to govern it.*

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Tests](https://img.shields.io/badge/Tests-55%20unit%20%2B%2015%20UI-brightgreen)](.)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](LICENSE)

</div>

---

## What It Does

Claude Session Hub reads your local Claude Code data (`~/.claude/`) and gives you a unified dashboard to manage all your sessions across projects. No API calls, no network, fully offline.

**Sessions View** — Browse sessions by project, with 3-layer tiles showing title, task summary, health signals, and engineering metadata.

**Overview Dashboard** — Project portfolio + attention inbox. See which sessions need attention, which are active, and navigate to any project in one click.

**Health Signals** — Conditional alerts that surface problems without cluttering healthy sessions:
- Stale sessions (inactive 2+ days, not done)
- Context near full (75%+ of model limit)
- Recent errors (from last 20 turns)

## Features

- **Project → Session hierarchy** with sectioned sidebar (Agents / Projects / Status)
- **3-layer session tiles** with conditional health signals (max 2 per tile)
- **Overview dashboard** with summary cards, project heat strip, attention inbox, project portfolio
- **One-click resume** in Ghostty or Terminal.app with silent clipboard fallback
- **Manual labels** — double-click to rename any session
- **Session archiving** — hide completed sessions, toggle visibility
- **Structured fact extraction** from Claude Code JSONL (not guesswork)
- **Full prompt-context accounting** — `input_tokens + cache_creation + cache_read`
- **Provider abstraction** — Claude Code first, Codex ready
- **Keyboard shortcuts** — Cmd+F (search), Cmd+, (settings), Esc (clear)

## Quick Start

### Download

Grab the latest `.zip` from [Releases](https://github.com/MedivhStory/ClaudeSessionHub/releases), unzip, and double-click `ClaudeSessionHub.app`.

> First launch: macOS may show a Gatekeeper warning. Right-click the app and select "Open" to bypass.

### Run from Source

```bash
git clone https://github.com/MedivhStory/ClaudeSessionHub.git
cd ClaudeSessionHub
swift run ClaudeSessionHub
```

### Run from Xcode

1. Open `Package.swift` in Xcode
2. Select the **ClaudeSessionHub** scheme, destination **My Mac**
3. Cmd+R

### Build Standalone .app

```bash
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -target ClaudeSessionHub \
  -configuration Release \
  build CONFIGURATION_BUILD_DIR=./dist

# Embed app icon
mkdir -p dist/ClaudeSessionHub.app/Contents/Resources
cp Resources/AppIcon.icns dist/ClaudeSessionHub.app/Contents/Resources/
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
  dist/ClaudeSessionHub.app/Contents/Info.plist 2>/dev/null

open dist/ClaudeSessionHub.app
```

## Testing

```bash
# Unit tests (55 tests)
swift test

# UI tests (15 tests, requires Xcode)
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -scheme ClaudeSessionHub \
  -destination 'platform=macOS' \
  test -only-testing:'ClaudeSessionHubUITests'
```

UI tests use a deterministic fixture mode (`--ui-test-mode`) with 4 synthetic sessions — no real `~/.claude/` data needed.

## Architecture

```
┌─────────────────────────────────────┐
│  SessionStore (@Observable)         │  SwiftUI binds here
├─────────────────────────────────────┤
│  ScanCoordinator                    │  Runs providers concurrently
├─────────────────────────────────────┤
│  Canonical Models                   │  SessionSummary, SessionDetail,
│                                     │  HealthSignal, ResumeTarget
├─────────────────────────────────────┤
│  AgentProvider (protocol)           │  ClaudeProvider, CodexProvider (stub)
│  Reads ~/.claude/ JSONL             │  Emits canonical types only
└─────────────────────────────────────┘
```

**Data sources** (read-only, never modified):

| Source | Path | Purpose |
|---|---|---|
| Session JSONL | `~/.claude/projects/<key>/<id>.jsonl` | Session content |
| Process metadata | `~/.claude/sessions/<pid>.json` | PID liveness |
| History index | `~/.claude/history.jsonl` | Fast session lookup |

**App settings** stored in `~/.claude-hub/` (labels, archive state, preferences).

## Requirements

- **macOS 14** (Sonoma) or later
- **Swift 5.9+**
- **Xcode 26+** (for building .app and running UI tests)
- Claude Code installed (the app reads its local data)

## Current Limitations

- Codex provider is a stub (protocol ready, no implementation yet)
- Data directory changes require app restart
- No code signing or notarization
- `recentErrorCount` uses tail-50 approximation, not exact last-20-turns

## License

MIT

---

<div align="center">

*Enjoy AI, but don't forget to govern it.*

Built with SwiftUI. Designed for Claude Code power users.

</div>
