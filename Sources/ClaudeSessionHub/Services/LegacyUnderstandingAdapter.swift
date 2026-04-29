import Foundation

/// Read-only adapter over `~/.claude-hub/understanding.json` (V1 format).
/// Produces optional `LegacyUnderstandingSnapshot` for sessions that have
/// pre-v0.2.9 AI understanding data.
///
/// The adapter NEVER writes to or mutates `understanding.json`. It exists
/// purely to expose legacy data to the v0.2.9 display policy as
/// "Pre-v0.2.9 baseline" candidates.
///
/// Decoding is lenient: missing fields are tolerated. This handles partial
/// V1 records and lets callers see whatever was preserved.
public final class LegacyUnderstandingAdapter: @unchecked Sendable {

    private let filePath: String
    private let lock = NSLock()
    private var snapshotsByID: [String: LegacyUnderstandingSnapshot] = [:]
    private var loaded = false

    public init(directory: String = NSHomeDirectory() + "/.claude-hub") {
        self.filePath = (directory as NSString).appendingPathComponent("understanding.json")
    }

    /// Returns the legacy snapshot for `sessionID`, or nil if no V1 data
    /// exists for that session.
    public func legacySnapshot(for sessionID: String) -> LegacyUnderstandingSnapshot? {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return snapshotsByID[sessionID]
    }

    /// Drop the cached load. The next call to `legacySnapshot(for:)` will
    /// re-read from disk. Provided for tests; not used by production code.
    public func invalidateCache() {
        lock.lock(); defer { lock.unlock() }
        loaded = false
        snapshotsByID = [:]
    }

    // MARK: - Private

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        guard let data = FileManager.default.contents(atPath: filePath) else {
            return // missing file → empty
        }

        // Default JSONDecoder matches the V1 producer (UnderstandingStore),
        // which uses default JSONEncoder. Date format is
        // secondsSinceReferenceDate.
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode([String: LooseV1Snapshot].self, from: data) else {
            fputs("warn: failed to decode understanding.json (legacy v1)\n", stderr)
            return
        }

        snapshotsByID = raw.mapValues { v1 in
            LegacyUnderstandingSnapshot(
                title: v1.title,
                progress: v1.progress,
                summary: v1.summary,
                generatedAt: v1.generatedAt,
                modelName: v1.modelName
            )
        }
    }
}

// MARK: - Loose V1 schema

/// Lenient v1 snapshot decoding: every field is optional. Real v1 files
/// always carried `title`, `modelName`, `generatedAt`, and
/// `basedOnLastActiveAt`, but the adapter is defensive against partial or
/// hand-written legacy data. `basedOnLastActiveAt` is intentionally
/// dropped: legacy data carries no trustworthy staleness signal under the
/// v0.2.9 model (`StaleState.legacyUnknown` covers this case).
private struct LooseV1Snapshot: Decodable {
    let title: String?
    let progress: String?
    let summary: String?
    let generatedAt: Date?
    let modelName: String?
}
