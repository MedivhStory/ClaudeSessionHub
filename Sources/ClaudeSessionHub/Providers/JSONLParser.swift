import Foundation

/// Efficient JSONL parser that reads first N and last N entries without loading the full file.
public enum JSONLParser {
    /// Read first `count` parseable JSON entries from file
    public static func readFirstEntries(at path: String, count: Int) throws -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { handle.closeFile() }

        let chunkSize = 8192
        var buffer = Data()
        var entries: [[String: Any]] = []

        while entries.count < count {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                buffer = Data(buffer[newlineRange.upperBound...])

                if let entry = parseLine(lineData) {
                    entries.append(entry)
                    if entries.count >= count { break }
                }
            }
        }
        // Handle last line without trailing newline
        if entries.count < count, !buffer.isEmpty, let entry = parseLine(buffer) {
            entries.append(entry)
        }
        return entries
    }

    /// Read last `count` parseable JSON entries from file via reverse scan
    public static func readLastEntries(at path: String, count: Int) throws -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return [] }

        let chunkSize: UInt64 = 8192
        var entries: [[String: Any]] = []
        var offset = fileSize
        var trailingData = Data()

        while entries.count < count && offset > 0 {
            let readSize = min(chunkSize, offset)
            offset -= readSize
            handle.seek(toFileOffset: offset)
            var chunk = handle.readData(ofLength: Int(readSize))
            chunk.append(trailingData)
            trailingData = Data()

            var lines: [Data] = []
            while let newlineRange = chunk.range(of: Data([0x0A]), options: .backwards) {
                let lineData = chunk[chunk.index(after: newlineRange.lowerBound)...]
                if !lineData.isEmpty {
                    lines.append(Data(lineData))
                }
                chunk = Data(chunk[chunk.startIndex..<newlineRange.lowerBound])
            }
            if !chunk.isEmpty {
                trailingData = Data(chunk)
            }

            for lineData in lines {
                if let entry = parseLine(lineData) {
                    entries.append(entry)
                    if entries.count >= count { break }
                }
            }
        }

        if entries.count < count && !trailingData.isEmpty {
            if let entry = parseLine(trailingData) {
                entries.append(entry)
            }
        }

        return entries.reversed() // Return in chronological order
    }

    /// Read ALL parseable JSON entries from file (line by line streaming)
    public static func readAllEntries(at path: String) throws -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { handle.closeFile() }

        let chunkSize = 65536
        var buffer = Data()
        var entries: [[String: Any]] = []

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                // Process remaining buffer
                if !buffer.isEmpty, let entry = parseLine(buffer) {
                    entries.append(entry)
                }
                break
            }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                buffer = Data(buffer[newlineRange.upperBound...])

                if let entry = parseLine(lineData) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    /// Read user-type entries sampled evenly from the middle of the file.
    public static func readSampledUserTurns(
        at path: String,
        count: Int,
        skipHead: Int = 10,
        skipTail: Int = 50
    ) throws -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { try? handle.close() }

        // ─── Pass 1: byte-scan total line count ───
        var totalLines = 0
        var sawAnyByte = false
        var lastByte: UInt8 = 0
        try handle.seek(toOffset: 0)
        let chunkSize = 65536
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            sawAnyByte = true
            chunk.forEach { byte in
                if byte == 0x0A { totalLines += 1 }
            }
            if let last = chunk.last { lastByte = last }
        }
        // Final line without trailing \n counts as one more line
        if sawAnyByte && lastByte != 0x0A { totalLines += 1 }

        // ─── Bounds ───
        let middleStart = skipHead
        let middleEnd = totalLines - skipTail
        let middleSize = middleEnd - middleStart
        if middleSize <= 0 { return [] }
        let actualK = min(count, middleSize)
        if actualK <= 0 { return [] }

        // ─── Bucket centers ───
        let bucketWidth = Double(middleSize) / Double(actualK)
        var bucketCenters: [Int] = []
        for i in 0..<actualK {
            let center = middleStart + Int((Double(i) + 0.5) * bucketWidth)
            bucketCenters.append(min(center, middleEnd - 1))
        }

        // ─── Pass 2: streaming line extraction with bucket-center selection ───
        var bestEntry: [Int: [String: Any]] = [:]
        var bestDistance: [Int: Int] = [:]
        var buffer = Data()
        var lineIndex = 0
        var stop = false

        func processLine(_ lineData: Data) {
            defer { lineIndex += 1 }

            // Skip header range
            if lineIndex < middleStart { return }
            // Skip tail range
            if lineIndex >= middleEnd { return }

            // Parse JSON; skip malformed lines silently
            guard let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return }

            // Qualifying user turn filter — must carry real user text.
            //
            // Claude Code user entries can take three shapes:
            //   1. `message.content` as String              → real text (legacy/slash-command path)
            //   2. `message.content` as [text blocks]       → real text (structured content API)
            //   3. `message.content` as [tool_result, ...]  → tool call return, NOT user intent
            //
            // Shape 3 is noise and previously dominated middle samples in
            // heavy-tool sessions, starving the LLM prompt of real text turns.
            // Accept shapes 1 and 2; reject shape 3.
            guard parsed["type"] as? String == "user",
                  (parsed["isMeta"] as? Bool) != true,
                  let message = parsed["message"] as? [String: Any] else { return }
            let content = message["content"]
            if content is String {
                // Shape 1 — accept
            } else if let blocks = content as? [[String: Any]] {
                // Shape 2 vs 3 — accept only if at least one block is a text block
                let hasTextBlock = blocks.contains { block in
                    (block["type"] as? String) == "text" &&
                    !((block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                }
                guard hasTextBlock else { return }
            } else {
                return
            }

            // Determine bucket
            let offsetInMiddle = lineIndex - middleStart
            var bucketIdx = Int(Double(offsetInMiddle) / bucketWidth)
            if bucketIdx >= actualK { bucketIdx = actualK - 1 }
            if bucketIdx < 0 { bucketIdx = 0 }

            let dist = abs(lineIndex - bucketCenters[bucketIdx])

            if let currentBest = bestDistance[bucketIdx] {
                if dist < currentBest {
                    bestEntry[bucketIdx] = parsed
                    bestDistance[bucketIdx] = dist
                }
                // else if dist == currentBest: earlier wins (already stored).
                // This branch is deliberately a no-op — NOT `break`, NOT `continue`.
                // else if dist > currentBest: also no-op.
            } else {
                bestEntry[bucketIdx] = parsed
                bestDistance[bucketIdx] = dist
            }
        }

        try handle.seek(toOffset: 0)
        while !stop {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            // Drain all complete newline-delimited lines
            while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: 0..<newlineIdx)
                buffer.removeSubrange(0...newlineIdx)
                processLine(lineData)
                if lineIndex >= middleEnd { stop = true; break }
            }
            if lineIndex >= middleEnd { stop = true; break }
        }

        // ─── EOF flush: handle unterminated final line ───
        //
        // Invariant: after the chunk loop exits normally, `buffer` contains AT
        // MOST ONE unterminated line (the file's final line without trailing \n).
        // The inner `while let newlineIdx = ...` loop drained every complete line
        // before exiting. No loop needed here — at most one processLine call.
        //
        // If the outer loop exited because lineIndex >= middleEnd (early break),
        // the residual buffer contents are past middleEnd and should be discarded.
        // The `lineIndex < middleEnd` guard below enforces this.
        if !buffer.isEmpty && lineIndex < middleEnd {
            processLine(buffer)
            buffer.removeAll()
        }

        // ─── Finalize ───
        var result: [[String: Any]] = []
        for i in 0..<actualK {
            if let entry = bestEntry[i] {
                result.append(entry)
            }
            // else: bucket had no qualifying user turn; slot left empty.
        }
        return result
    }

    private static func parseLine(_ data: Data) -> [String: Any]? {
        var start = data.startIndex
        var end = data.endIndex
        let ws: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        while start < end, ws.contains(data[start]) { start = data.index(after: start) }
        while end > start, ws.contains(data[data.index(before: end)]) { end = data.index(before: end) }
        guard start < end else { return nil }
        let trimmed = data[start..<end]
        return try? JSONSerialization.jsonObject(with: trimmed) as? [String: Any]
    }
}
