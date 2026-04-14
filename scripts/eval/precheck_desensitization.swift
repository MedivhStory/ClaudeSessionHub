#!/usr/bin/env swift
// scripts/eval/precheck_desensitization.swift
//
// Standalone pre-check script: compares a raw Claude Code session JSONL against
// a desensitized snapshot *.input.json for structural fidelity.
//
// Usage:
//   swift scripts/eval/precheck_desensitization.swift --raw <path.jsonl> --snapshot <path.input.json>
//
// IMPORTANT: This file MUST NOT import ClaudeSessionHubLib or any project module.
// It uses Foundation only and maintains its OWN regex constants (spec I-10 decoupling requirement).

import Foundation

// MARK: - Independently-maintained constants (do NOT share with product code)

let semverRegex = try! NSRegularExpression(pattern: #"(?i)v?\d+\.\d+(\.\d+)?"#)
let milestoneKeywords = ["版本", "封版", "release", "tag", "milestone"]

// MARK: - Fatal error helper

func die(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}

// MARK: - Argument parsing

var args = CommandLine.arguments.dropFirst()

func nextArg(after flag: String) -> String? {
    var it = args.makeIterator()
    while let a = it.next() {
        if a == flag { return it.next() }
    }
    return nil
}

guard let rawPath = nextArg(after: "--raw") else {
    die("--raw <path> is required")
}
guard let snapshotPath = nextArg(after: "--snapshot") else {
    die("--snapshot <path> is required")
}

// MARK: - Read raw JSONL

guard FileManager.default.fileExists(atPath: rawPath) else {
    die("raw JSONL not found: \(rawPath)")
}
guard FileManager.default.fileExists(atPath: snapshotPath) else {
    die("snapshot JSON not found: \(snapshotPath)")
}

let rawContents: String
do {
    rawContents = try String(contentsOfFile: rawPath, encoding: .utf8)
} catch {
    die("cannot read raw JSONL: \(error)")
}

// MARK: - Analyse raw JSONL

let rawLines = rawContents.components(separatedBy: "\n").filter {
    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
let totalRawLines = rawLines.count

var rawUserTurnCount = 0
var rawVersionMentionCount = 0
var rawMilestoneHits: [String] = []

for line in rawLines {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        continue
    }

    // Count user turns (non-meta, type == "user")
    if json["type"] as? String == "user" && json["isMeta"] as? Bool != true {
        rawUserTurnCount += 1

        // Extract string content for analysis
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            // Count version mentions
            let nsContent = content as NSString
            let range = NSRange(location: 0, length: nsContent.length)
            let matches = semverRegex.numberOfMatches(in: content, range: range)
            rawVersionMentionCount += matches

            // Check milestone keywords
            for kw in milestoneKeywords {
                if content.contains(kw) {
                    rawMilestoneHits.append(kw)
                }
            }
        }
    }
}

let rawUniqueMilestoneHits = Array(Set(rawMilestoneHits)).sorted()

// MARK: - Read snapshot JSON

let snapshotData: Data
do {
    snapshotData = try Data(contentsOf: URL(fileURLWithPath: snapshotPath))
} catch {
    die("cannot read snapshot JSON: \(error)")
}

guard let snapshotJSON = try? JSONSerialization.jsonObject(with: snapshotData) as? [String: Any] else {
    die("snapshot is not valid JSON: \(snapshotPath)")
}

// Navigate: input.signals.historyDisplayTexts
let inputBlock = snapshotJSON["input"] as? [String: Any]
let signalsBlock = inputBlock?["signals"] as? [String: Any]
let rawTurnsArr = (inputBlock?["rawTurns"] as? [String]) ?? []
let historyDisplayTexts = (signalsBlock?["historyDisplayTexts"] as? [String]) ?? []
let snapshotVersionMentions = (signalsBlock?["versionMentions"] as? [[String: Any]]) ?? []
let snapshotTurnCount = signalsBlock?["turnCount"] as? Int ?? 0
let snapshotSessionID = signalsBlock?["sessionID"] as? String ?? "(missing)"

// Count version mentions in snapshot
let snapshotVersionMentionCount = snapshotVersionMentions.count

// Check milestone keywords in historyDisplayTexts
var snapshotMilestoneHits: [String] = []
for text in historyDisplayTexts {
    for kw in milestoneKeywords {
        if text.contains(kw) {
            snapshotMilestoneHits.append(kw)
        }
    }
}
let snapshotUniqueMilestoneHits = Array(Set(snapshotMilestoneHits)).sorted()

// MARK: - Print comparison table

print("")
print("═══════════════════════════════════════════════════════════")
print("  precheck_desensitization — structural fidelity report")
print("═══════════════════════════════════════════════════════════")
print("")
print("  Snapshot ID    : \(snapshotSessionID)")
print("  Raw JSONL      : \(rawPath)")
print("  Snapshot JSON  : \(snapshotPath)")
print("")
print("  ┌─────────────────────────────┬──────────┬──────────────┐")
print("  │ Metric                      │ Raw JSONL│ Snapshot JSON│")
print("  ├─────────────────────────────┼──────────┼──────────────┤")

func padded(_ s: String, width: Int) -> String {
    if s.count >= width { return String(s.prefix(width)) }
    return s + String(repeating: " ", count: width - s.count)
}

func row(_ label: String, _ raw: String, _ snap: String, flagMismatch: Bool = false) {
    let marker = flagMismatch ? " !" : "  "
    print("\(marker)│ \(padded(label, width: 27))│ \(padded(raw, width: 8)) │ \(padded(snap, width: 12)) │")
}

row("Total JSONL lines", "\(totalRawLines)", "(N/A)")
row("User turns", "\(rawUserTurnCount)", "\(snapshotTurnCount)",
    flagMismatch: rawUserTurnCount > 0 && snapshotTurnCount == 0)
row("historyDisplayTexts", "(N/A)", "\(historyDisplayTexts.count)")
row("rawTurns (sampled)", "(N/A)", "\(rawTurnsArr.count)")
row("Version mentions", "\(rawVersionMentionCount)", "\(snapshotVersionMentionCount)")
row("Milestone kw hits", "\(rawUniqueMilestoneHits.count)", "\(snapshotUniqueMilestoneHits.count)")

print("  └─────────────────────────────┴──────────┴──────────────┘")
print("")

// MARK: - Flag discrepancies

var discrepancies: [String] = []

// User turns: snapshot turnCount should be > 0 if raw has user turns
if rawUserTurnCount > 0 && snapshotTurnCount == 0 {
    discrepancies.append("WARN: raw has \(rawUserTurnCount) user turn(s) but snapshot.signals.turnCount == 0")
}

// historyDisplayTexts should not be empty if raw has user content
if rawUserTurnCount > 0 && historyDisplayTexts.isEmpty {
    discrepancies.append("WARN: raw has user turns but snapshot.signals.historyDisplayTexts is empty")
}

// rawTurns: sampled slice should be non-empty if there are user turns
if rawUserTurnCount > 0 && rawTurnsArr.isEmpty {
    discrepancies.append("WARN: raw has user turns but snapshot.input.rawTurns is empty")
}

// Version mentions: snapshot should have >= 1 if raw has >= 3
if rawVersionMentionCount >= 3 && snapshotVersionMentionCount == 0 {
    discrepancies.append("WARN: raw has \(rawVersionMentionCount) semver-like token(s) but snapshot.signals.versionMentions is empty")
}

// Milestone keywords: alert if hits differ significantly
let rawMilestoneSet = Set(rawUniqueMilestoneHits)
let snapMilestoneSet = Set(snapshotUniqueMilestoneHits)
let missingInSnap = rawMilestoneSet.subtracting(snapMilestoneSet)
if !missingInSnap.isEmpty {
    discrepancies.append("INFO: milestone keywords found in raw but absent from snapshot historyDisplayTexts: \(missingInSnap.sorted().joined(separator: ", "))")
}

if discrepancies.isEmpty {
    print("  ✓ No structural discrepancies detected.")
} else {
    print("  Discrepancies:")
    for d in discrepancies {
        print("    • \(d)")
    }
}

print("")
print("  Note: Minor deltas in user-turn count are expected (noise")
print("  filtering, meta entries). Review flagged items manually.")
print("")
