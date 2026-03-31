# Claude Session Hub

A native macOS task manager for Claude Code sessions. Discovers, organizes, and surfaces session health across projects.

## Features

- **Project → Session hierarchy** with sectioned sidebar
- **3-layer session tiles** with conditional health signals (stale, context near full, errors)
- **Overview dashboard** with project portfolio + attention inbox
- **One-click resume** in Ghostty or Terminal.app with silent fallback
- **Manual labels** and session archiving
- **Structured fact extraction** from Claude Code JSONL data
- **Provider abstraction** (Claude Code supported, Codex stub ready)

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Xcode 26+ (for UI tests and .app building)

## Quick Start

### Run from command line
```bash
swift run ClaudeSessionHub
```

### Run from Xcode
1. Open `Package.swift` in Xcode
2. Select the `ClaudeSessionHub` scheme
3. Press Cmd+R

### Build standalone .app
```bash
xcodebuild -project ClaudeSessionHub.xcodeproj -target ClaudeSessionHub -configuration Release build CONFIGURATION_BUILD_DIR=./dist
open dist/ClaudeSessionHub.app
```

## Testing

### Unit tests (55 tests)
```bash
swift test
```

### UI tests (15 tests, requires Xcode)
```bash
xcodebuild -project ClaudeSessionHub.xcodeproj -scheme ClaudeSessionHub -destination 'platform=macOS' test -only-testing:'ClaudeSessionHubUITests'
```

## Data Sources

The app reads (never modifies) Claude Code data from:
- `~/.claude/projects/` — session JSONL files
- `~/.claude/sessions/` — process metadata
- `~/.claude/history.jsonl` — session index

App settings are stored in `~/.claude-hub/`.

## Current Limitations

- Codex provider is a stub (interface ready, no implementation)
- Data directory changes require app restart
- No code signing or notarization (runs with Gatekeeper bypass)
- App icon is the default SwiftUI placeholder
