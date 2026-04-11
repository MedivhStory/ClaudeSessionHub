import Foundation

public enum MilestoneSamplerConstants {
    public static let kFloor = 4
    public static let kCeiling = 8
    public static let kDivisor = 10
}

public enum MilestoneSampler {
    public static func adaptiveK(historyCount: Int) -> Int {
        if historyCount <= 0 { return 0 }
        let raw = max(MilestoneSamplerConstants.kFloor, historyCount / MilestoneSamplerConstants.kDivisor)
        let capped = min(MilestoneSamplerConstants.kCeiling, raw)
        return min(historyCount, capped)
    }

    public static func sample(
        history: [String],
        versionMentions: [VersionMention],
        K: Int
    ) -> [MilestoneEntry] {
        if history.isEmpty { return [] }
        var mandatory: [Int: [MilestoneEntry.Reason]] = [:]

        // Short session branch
        if history.count <= K {
            for i in 0..<history.count {
                var rs: [MilestoneEntry.Reason] = []
                if i == 0 { rs.append(.firstEntry) }
                if i == history.count - 1 { rs.append(.lastEntry) }
                // Middle entries reuse .timeFill with bucket=i, totalBuckets=history.count (I-13)
                if i != 0 && i != history.count - 1 {
                    rs.append(.timeFill(bucket: i, totalBuckets: history.count))
                }
                mandatory[i] = rs
            }
            applyVersionAnchors(&mandatory, versionMentions, history.count)
            return finalize(mandatory, history)
        }

        // Long session branch
        mandatory[0] = [.firstEntry]
        mandatory[history.count - 1] = (mandatory[history.count - 1, default: []]) + [.lastEntry]
        applyVersionAnchors(&mandatory, versionMentions, history.count)

        if mandatory.count > K {
            truncateMandatory(&mandatory, versionMentions, K: K)
            return finalize(mandatory, history)
        }

        runTimeFill(&mandatory, historyCount: history.count, K: K)
        return finalize(mandatory, history)
    }

    // MARK: - Helpers

    private static func applyVersionAnchors(
        _ mandatory: inout [Int: [MilestoneEntry.Reason]],
        _ versionMentions: [VersionMention],
        _ historyCount: Int
    ) {
        for vm in versionMentions {
            // Only history-anchored versions become milestone anchors.
            // Non-history versionMentions remain in signals.versionMentions for prompt consumption.
            guard vm.selectedSource.kind == .history,
                  let idx = vm.selectedSource.index,
                  idx >= 0, idx < historyCount else { continue }
            mandatory[idx, default: []].append(
                .versionAnchor(normalizedVersion: vm.normalized)
            )
        }
    }

    private static func truncateMandatory(
        _ mandatory: inout [Int: [MilestoneEntry.Reason]],
        _ versionMentions: [VersionMention],
        K: Int
    ) {
        // Protect firstEntry/lastEntry entries (at most 2 slots)
        var protectedIndices = Set<Int>()
        for (idx, reasons) in mandatory {
            if reasons.contains(.firstEntry) || reasons.contains(.lastEntry) {
                protectedIndices.insert(idx)
            }
        }
        let remainingSlots = K - protectedIndices.count
        if remainingSlots <= 0 {
            mandatory = mandatory.filter { protectedIndices.contains($0.key) }
            return
        }

        // Score non-protected indices by their representative version
        let nonProtected = mandatory.keys.filter { !protectedIndices.contains($0) }
        struct Scored { let idx: Int; let topOccurrence: Int; let topNormalized: String }

        let scored: [Scored] = nonProtected.map { idx in
            let vms = versionMentions.filter {
                $0.selectedSource.kind == .history && $0.selectedSource.index == idx
            }
            // Find representative: highest occurrenceCount, ties broken by normalized ascending
            let top = vms.max { a, b in
                if a.occurrenceCount != b.occurrenceCount {
                    return a.occurrenceCount < b.occurrenceCount
                }
                return a.normalized > b.normalized   // max with > gives ascending tiebreaker
            }!
            return Scored(idx: idx, topOccurrence: top.occurrenceCount, topNormalized: top.normalized)
        }

        // Sort by priority (occurrence desc, normalized asc)
        let sorted = scored.sorted { a, b in
            if a.topOccurrence != b.topOccurrence {
                return a.topOccurrence > b.topOccurrence
            }
            return a.topNormalized < b.topNormalized
        }

        let keptIndices = Set(sorted.prefix(remainingSlots).map { $0.idx })
        let finalKept = protectedIndices.union(keptIndices)

        // Remove non-kept entries. Truncated version anchors remain in signals.versionMentions.
        mandatory = mandatory.filter { finalKept.contains($0.key) }
    }

    private static func runTimeFill(
        _ mandatory: inout [Int: [MilestoneEntry.Reason]],
        historyCount: Int,
        K: Int
    ) {
        if mandatory.count >= K { return }
        let slotsRemaining = K - mandatory.count
        let bucketWidth = Double(historyCount) / Double(slotsRemaining)

        for bucket in 0..<slotsRemaining {
            let center = min(
                Int((Double(bucket) + 0.5) * bucketWidth),
                historyCount - 1
            )
            let occupied = Set(mandatory.keys)
            guard let idx = findNearestUnoccupied(
                center: center,
                occupied: occupied,
                range: 0..<historyCount
            ) else {
                // Unreachable: mandatory.count < K <= historyCount guarantees an
                // unoccupied slot exists in [0, historyCount).
                preconditionFailure("MilestoneSampler.runTimeFill: findNearestUnoccupied returned nil at bucket=\(bucket), center=\(center), mandatory.count=\(mandatory.count), historyCount=\(historyCount), K=\(K), slotsRemaining=\(slotsRemaining) — invariant violated")
            }
            mandatory[idx] = [.timeFill(bucket: bucket, totalBuckets: slotsRemaining)]
        }
    }

    private static func findNearestUnoccupied(
        center: Int,
        occupied: Set<Int>,
        range: Range<Int>
    ) -> Int? {
        if range.contains(center) && !occupied.contains(center) {
            return center
        }
        // Expand outward; on ties, prefer earlier (center - offset)
        for offset in 1..<range.count {
            let left = center - offset
            if range.contains(left) && !occupied.contains(left) {
                return left
            }
            let right = center + offset
            if range.contains(right) && !occupied.contains(right) {
                return right
            }
        }
        return nil
    }

    private static func sortReasons(_ reasons: [MilestoneEntry.Reason]) -> [MilestoneEntry.Reason] {
        // I-13 deterministic order:
        // 1. .firstEntry (at most 1)
        // 2. .versionAnchor sorted by normalized ascending
        // 3. .lastEntry (at most 1)
        // 4. .timeFill (at most 1)
        var firstEntries: [MilestoneEntry.Reason] = []
        var versionAnchors: [MilestoneEntry.Reason] = []
        var lastEntries: [MilestoneEntry.Reason] = []
        var timeFills: [MilestoneEntry.Reason] = []

        for r in reasons {
            switch r {
            case .firstEntry: firstEntries.append(r)
            case .versionAnchor: versionAnchors.append(r)
            case .lastEntry: lastEntries.append(r)
            case .timeFill: timeFills.append(r)
            }
        }

        versionAnchors.sort { a, b in
            guard case let .versionAnchor(na) = a, case let .versionAnchor(nb) = b else {
                return false
            }
            return na < nb
        }

        return firstEntries + versionAnchors + lastEntries + timeFills
    }

    private static func finalize(
        _ mandatory: [Int: [MilestoneEntry.Reason]],
        _ history: [String]
    ) -> [MilestoneEntry] {
        return mandatory.keys.sorted().map { idx in
            MilestoneEntry(
                index: idx,
                totalCount: history.count,
                text: history[idx],
                reasons: sortReasons(mandatory[idx]!)
            )
        }
    }
}
