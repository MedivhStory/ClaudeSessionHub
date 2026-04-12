// Sources/DesensitizeSession/main.swift
// Internal operator tool — NOT a public product.
// Reads a raw Claude Code session JSONL, applies text replacements from mapping CSVs,
// and outputs a *.input.json fixture file conforming to FixtureInputFile schema.
//
// Usage:
//   DesensitizeSession \
//     --input  <path-to-raw.jsonl> \
//     --mapping <dir-with-csv-files> \
//     --output  <path-to-output.input.json> \
//     --id      <fixture-id> \
//     --failure-mode <string-or-"none"> \
//     --description <string>

import Foundation
import ClaudeSessionHubLib
import EvalHarnessCore

// MARK: - Fatal error helper

func die(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}

// MARK: - Argument parsing

var args = CommandLine.arguments.dropFirst()  // drop program name

func nextArg(after flag: String) -> String? {
    var it = args.makeIterator()
    while let a = it.next() {
        if a == flag { return it.next() }
    }
    return nil
}

guard let inputPath = nextArg(after: "--input") else { die("--input <path> is required") }
guard let mappingDir = nextArg(after: "--mapping") else { die("--mapping <dir> is required") }
guard let outputPath = nextArg(after: "--output") else { die("--output <path> is required") }
guard let fixtureID = nextArg(after: "--id") else { die("--id <fixture-id> is required") }
let failureModeRaw = nextArg(after: "--failure-mode")
guard let description = nextArg(after: "--description") else { die("--description <string> is required") }

let failureMode: String? = (failureModeRaw == nil || failureModeRaw == "none") ? nil : failureModeRaw

// MARK: - CSV mapping loader

/// Loads a CSV file of the form `original,replacement` (one pair per line).
/// Lines that are blank or start with `#` are skipped.
func loadMappingCSV(atPath path: String) throws -> [(original: String, replacement: String)] {
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    var pairs: [(String, String)] = []
    for line in contents.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        // Split on first comma only
        guard let commaIdx = trimmed.firstIndex(of: ",") else { continue }
        let original = String(trimmed[trimmed.startIndex..<commaIdx])
        let replacement = String(trimmed[trimmed.index(after: commaIdx)...])
        if original.isEmpty { continue }
        pairs.append((original, replacement))
    }
    return pairs
}

/// Applies all replacement pairs to a string, longest-first to avoid partial matches.
func applyReplacements(_ text: String, mappings: [(original: String, replacement: String)]) -> String {
    // Sort by descending original length so longer tokens shadow shorter prefixes.
    let sorted = mappings.sorted { $0.original.count > $1.original.count }
    var result = text
    for (original, replacement) in sorted {
        result = result.replacingOccurrences(of: original, with: replacement)
    }
    return result
}

// MARK: - Load mappings

var allMappings: [(original: String, replacement: String)] = []

let fm = FileManager.default
guard fm.fileExists(atPath: mappingDir) else { die("mapping directory does not exist: \(mappingDir)") }

for csvName in ["usernames.csv", "paths.csv", "repos.csv"] {
    let csvPath = mappingDir + "/" + csvName
    if fm.fileExists(atPath: csvPath) {
        do {
            let pairs = try loadMappingCSV(atPath: csvPath)
            allMappings.append(contentsOf: pairs)
            fputs("info: loaded \(pairs.count) mapping(s) from \(csvName)\n", stderr)
        } catch {
            die("failed to read \(csvPath): \(error)")
        }
    } else {
        fputs("info: \(csvName) not found in mapping dir — skipping\n", stderr)
    }
}

// MARK: - Read raw JSONL and apply replacements

guard fm.fileExists(atPath: inputPath) else { die("input file does not exist: \(inputPath)") }

let rawContents: String
do {
    rawContents = try String(contentsOfFile: inputPath, encoding: .utf8)
} catch {
    die("failed to read input file \(inputPath): \(error)")
}

let rawLines = rawContents.components(separatedBy: "\n")

// Apply replacements line-by-line to keep memory bounded and avoid cross-line corruption.
let desensitizedLines = rawLines.map { line -> String in
    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return line }
    return applyReplacements(line, mappings: allMappings)
}

fputs("info: processed \(rawLines.count) raw lines\n", stderr)

// MARK: - Parse desensitized JSONL into entry dictionaries

var parsedEntries: [[String: Any]] = []
for line in desensitizedLines {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }
    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        fputs("warning: skipping non-parseable line: \(trimmed.prefix(80))\n", stderr)
        continue
    }
    parsedEntries.append(json)
}

fputs("info: parsed \(parsedEntries.count) JSON entries\n", stderr)

// MARK: - Helper: extract string content from a user JSONL entry

func extractStringContent(from entry: [String: Any]) -> String? {
    guard let message = entry["message"] as? [String: Any] else { return nil }
    if let content = message["content"] as? String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}

func isInternalNoise(_ content: String) -> Bool {
    let noisePrefixes = [
        "<local-command-stdout>", "<local-command-caveat>", "<command-name>",
        "<task-notification>", "<system-reminder>",
        "/resume", "/login", "/logout", "/clear"
    ]
    return noisePrefixes.contains(where: { content.hasPrefix($0) })
}

func extractTimestamp(from entry: [String: Any]) -> String? {
    entry["timestamp"] as? String
}

// MARK: - Extract signals from parsed entries

// Collect all non-meta user turns
let userTurnEntries = parsedEntries.filter { entry in
    guard entry["type"] as? String == "user" else { return false }
    guard entry["isMeta"] as? Bool != true else { return false }
    return true
}

let userContents: [String] = userTurnEntries.compactMap { extractStringContent(from: $0) }
    .filter { !isInternalNoise($0) }

let firstUserIntent = userContents.first
let lastUserIntent = userContents.count > 1 ? userContents.last : nil

// Last assistant progress (plain string content only)
var lastAssistantProgress: String? = nil
for entry in parsedEntries.reversed() {
    guard entry["type"] as? String == "assistant" else { continue }
    guard let message = entry["message"] as? [String: Any],
          let content = message["content"] as? String else { continue }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        lastAssistantProgress = String(trimmed.prefix(200))
        break
    }
}

// historyDisplayTexts: use non-noise user turn contents as a proxy
// (real history.jsonl is not available in raw JSONL; user turn summaries serve as substitute)
let historyDisplayTexts: [String] = userContents.filter { !$0.isEmpty }

// turnCount
let turnCount = userTurnEntries.count

// Branch and entrypoint
var branch: String? = nil
var entrypoint: String? = nil
for entry in parsedEntries {
    if branch == nil, let b = entry["branch"] as? String, !b.isEmpty { branch = b }
    if entrypoint == nil, let e = entry["type"] as? String, e == "system" {
        if let msg = entry["message"] as? [String: Any],
           let ep = msg["entrypoint"] as? String, !ep.isEmpty {
            entrypoint = ep
        }
    }
}

// slug — first non-empty slug field
var slug: String? = nil
for entry in parsedEntries {
    if let s = entry["slug"] as? String, !s.isEmpty { slug = s; break }
}

// Tools used and files modified
var toolsUsed: Set<String> = []
var filesModified: Set<String> = []
for entry in parsedEntries {
    if entry["type"] as? String == "assistant",
       let message = entry["message"] as? [String: Any],
       let contentArray = message["content"] as? [[String: Any]] {
        for item in contentArray {
            if item["type"] as? String == "tool_use",
               let toolName = item["name"] as? String {
                toolsUsed.insert(toolName)
                // Extract file paths from Write/Edit/Read tool inputs
                if ["Write", "Edit", "Read", "MultiEdit"].contains(toolName),
                   let input = item["input"] as? [String: Any],
                   let filePath = input["file_path"] as? String {
                    filesModified.insert(filePath)
                }
            }
        }
    }
}

// hasAssistantReply
let hasAssistantReply = parsedEntries.contains { $0["type"] as? String == "assistant" }

// totalEntryCount
let totalEntryCount = parsedEntries.count

// Last active timestamp (last entry with a timestamp)
let lastTimestamp = parsedEntries.reversed().compactMap { extractTimestamp(from: $0) }.first
    ?? ISO8601DateFormatter().string(from: Date())

// Session ID — derive from output filename or use fixture ID
let outputFilename = (outputPath as NSString).lastPathComponent
var sessionID = fixtureID
if outputFilename.hasSuffix(".input.json") {
    sessionID = String(outputFilename.dropLast(".input.json".count))
}

// MARK: - Build SessionSignals and extract version mentions

var signals = SessionSignals(sessionID: sessionID)
signals.firstUserIntent = firstUserIntent
signals.lastUserIntent = lastUserIntent
signals.lastAssistantProgress = lastAssistantProgress
signals.historyDisplayTexts = historyDisplayTexts
signals.branch = branch
signals.slug = slug
signals.entrypoint = entrypoint
signals.toolsUsed = toolsUsed
signals.filesModified = filesModified
signals.turnCount = turnCount
signals.hasAssistantReply = hasAssistantReply
signals.totalEntryCount = totalEntryCount
signals.historyCount = historyDisplayTexts.count

let versionMentions = VersionMentionExtractor.extract(from: signals)
fputs("info: extracted \(versionMentions.count) version mention(s)\n", stderr)

// MARK: - Sample rawTurns (head 2 + tail 2 + up to 2 middle samples)

func sampleRawTurns(from entries: [[String: Any]]) -> [String] {
    // Collect all non-noise user turn lines as JSON strings
    var turnLines: [String] = []
    for entry in entries {
        guard entry["type"] as? String == "user",
              entry["isMeta"] as? Bool != true,
              let content = extractStringContent(from: entry),
              !isInternalNoise(content) else { continue }
        // Format as a compact JSON line for rawTurns
        if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            turnLines.append(str)
        }
    }

    guard !turnLines.isEmpty else { return [] }

    let total = turnLines.count
    if total <= 6 {
        return turnLines  // small session: return all
    }

    var sampled: [String] = []

    // head 2
    sampled.append(contentsOf: turnLines.prefix(2))

    // middle 2 (evenly spaced from middle window)
    let middleStart = 2
    let middleEnd = total - 2
    let middleCount = middleEnd - middleStart
    if middleCount >= 2 {
        let step = middleCount / 2
        sampled.append(turnLines[middleStart + step / 2])
        sampled.append(turnLines[middleStart + step + step / 2])
    } else if middleCount == 1 {
        sampled.append(turnLines[middleStart])
    }

    // tail 2
    sampled.append(contentsOf: turnLines.suffix(2))

    return sampled
}

let rawTurns = sampleRawTurns(from: parsedEntries)
fputs("info: sampled \(rawTurns.count) raw turn(s)\n", stderr)

// MARK: - Build FixtureInputFile

let iso8601 = ISO8601DateFormatter()
iso8601.formatOptions = [.withInternetDateTime]
let desensitizedAt = iso8601.string(from: Date())

let meta = FixtureInputFile.Meta(
    failureMode: failureMode,
    description: description,
    desensitizedAt: desensitizedAt,
    desensitizationScriptVersion: "1.0.0"
)

let signalsPayload = FixtureInputFile.SignalsPayload(
    sessionID: sessionID,
    firstUserIntent: signals.firstUserIntent,
    lastUserIntent: signals.lastUserIntent,
    sampledUserIntents: signals.sampledUserIntents,
    lastAssistantProgress: signals.lastAssistantProgress,
    historyDisplayTexts: signals.historyDisplayTexts,
    versionMentions: versionMentions,
    taskSubject: signals.taskSubject,
    taskDescription: signals.taskDescription,
    taskStatus: signals.taskStatus,
    entrypoint: signals.entrypoint,
    branch: signals.branch,
    slug: signals.slug,
    toolsUsed: Array(signals.toolsUsed).sorted(),
    filesModified: Array(signals.filesModified).sorted(),
    isSidechain: signals.isSidechain,
    turnCount: signals.turnCount,
    slashCommands: signals.slashCommands,
    commandErrors: signals.commandErrors,
    hasAssistantReply: signals.hasAssistantReply,
    totalEntryCount: signals.totalEntryCount,
    historyCount: signals.historyCount
)

let input = FixtureInputFile.Input(
    signals: signalsPayload,
    rawTurns: rawTurns,
    basedOnLastActiveAt: lastTimestamp
)

let fixture = FixtureInputFile(
    schemaVersion: "1",
    id: fixtureID,
    kind: .realSnapshot,
    meta: meta,
    input: input
)

// MARK: - Encode and write output

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

let outputData: Data
do {
    outputData = try encoder.encode(fixture)
} catch {
    die("failed to encode fixture JSON: \(error)")
}

// Ensure parent directory exists
let outputDir = (outputPath as NSString).deletingLastPathComponent
if !outputDir.isEmpty && outputDir != "." {
    do {
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    } catch {
        die("failed to create output directory \(outputDir): \(error)")
    }
}

do {
    try outputData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    die("failed to write output file \(outputPath): \(error)")
}

fputs("ok: wrote fixture to \(outputPath)\n", stderr)
