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
    public static func readSampledUserTurns(at path: String, count: Int, skipHead: Int = 10, skipTail: Int = 50) throws -> [[String: Any]] {
        let allEntries = try readAllEntries(at: path)
        let total = allEntries.count
        guard total > skipHead + skipTail else { return [] }

        let middleEntries = Array(allEntries[skipHead..<(total - skipTail)])
        let userEntries = middleEntries.filter { entry in
            entry["type"] as? String == "user" &&
            entry["isMeta"] as? Bool != true
        }

        guard !userEntries.isEmpty else { return [] }
        if userEntries.count <= count { return userEntries }

        var sampled: [[String: Any]] = []
        let step = Double(userEntries.count) / Double(count)
        for i in 0..<count {
            let index = min(Int(Double(i) * step), userEntries.count - 1)
            sampled.append(userEntries[index])
        }
        return sampled
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
