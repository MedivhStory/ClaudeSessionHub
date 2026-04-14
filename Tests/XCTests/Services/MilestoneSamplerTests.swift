import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class MilestoneSamplerTests: XCTestCase {

    func test_adaptiveK_zero() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 0), 0) }
    func test_adaptiveK_one() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 1), 1) }
    func test_adaptiveK_two() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 2), 2) }
    func test_adaptiveK_three() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 3), 3) }
    func test_adaptiveK_four() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 4), 4) }
    func test_adaptiveK_39() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 39), 4) }
    func test_adaptiveK_40() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 40), 4) }
    func test_adaptiveK_50() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 50), 5) }
    func test_adaptiveK_60() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 60), 6) }
    func test_adaptiveK_70() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 70), 7) }
    func test_adaptiveK_80() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 80), 8) }
    func test_adaptiveK_200() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 200), 8) }
    func test_adaptiveK_smallHistory_doesNotExceedCount() {
        XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 2), 2)
    }

    func test_empty_history_returnsEmpty() {
        let result = MilestoneSampler.sample(history: [], versionMentions: [], K: 4)
        XCTAssertTrue(result.isEmpty)
    }

    func test_shortSession_returnsAll() {
        let history = ["a", "b", "c"]
        let result = MilestoneSampler.sample(history: history, versionMentions: [], K: 4)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].index, 0)
        XCTAssertEqual(result[1].index, 1)
        XCTAssertEqual(result[2].index, 2)
    }

    func test_shortSession_firstEntry_hasFirstEntryReason() {
        let result = MilestoneSampler.sample(history: ["a", "b", "c"], versionMentions: [], K: 4)
        XCTAssertTrue(result[0].reasons.contains(.firstEntry))
    }

    func test_shortSession_lastEntry_hasLastEntryReason() {
        let result = MilestoneSampler.sample(history: ["a", "b", "c"], versionMentions: [], K: 4)
        XCTAssertTrue(result[2].reasons.contains(.lastEntry))
    }

    func test_shortSession_middleEntry_hasTimeFillReason() {
        // Short-session middle entries reuse .timeFill (NOT .shortSessionEntry — I-13)
        let result = MilestoneSampler.sample(history: ["a", "b", "c"], versionMentions: [], K: 4)
        let middleReasons = result[1].reasons
        let hasTimeFill = middleReasons.contains { r in
            if case .timeFill = r { return true }
            return false
        }
        XCTAssertTrue(hasTimeFill)
    }

    func test_shortSession_middleEntry_withVersionAnchor_stacksReasons() {
        let vm = VersionMention(
            raw: "v0.2.5",
            normalized: "0.2.5",
            selectedSource: SourceRef(kind: .history, index: 1),
            occurrenceCount: 1
        )
        let result = MilestoneSampler.sample(history: ["a", "b v0.2.5", "c"], versionMentions: [vm], K: 4)
        let middleReasons = result[1].reasons
        XCTAssertTrue(middleReasons.contains(.versionAnchor(normalizedVersion: "0.2.5")))
        let hasTimeFill = middleReasons.contains { r in
            if case .timeFill = r { return true }
            return false
        }
        XCTAssertTrue(hasTimeFill)
    }

    func test_longSession_firstAndLastAlwaysSelected() {
        let history = (0..<20).map { "entry \($0)" }
        let result = MilestoneSampler.sample(history: history, versionMentions: [], K: 4)
        XCTAssertTrue(result.contains { $0.index == 0 && $0.reasons.contains(.firstEntry) })
        XCTAssertTrue(result.contains { $0.index == 19 && $0.reasons.contains(.lastEntry) })
    }

    func test_longSession_versionAnchorIncluded() {
        let history = (0..<20).map { "entry \($0)" }
        let vm = VersionMention(
            raw: "v0.2.5",
            normalized: "0.2.5",
            selectedSource: SourceRef(kind: .history, index: 10),
            occurrenceCount: 3
        )
        let result = MilestoneSampler.sample(history: history, versionMentions: [vm], K: 4)
        XCTAssertTrue(result.contains { $0.index == 10 })
    }

    func test_longSession_nonHistorySource_notMilestoneAnchor() {
        let history = (0..<20).map { "entry \($0)" }
        let vm = VersionMention(
            raw: "v0.2.5",
            normalized: "0.2.5",
            selectedSource: SourceRef(kind: .firstUserIntent),
            occurrenceCount: 1
        )
        let result = MilestoneSampler.sample(history: history, versionMentions: [vm], K: 4)
        // No entry should have .versionAnchor("0.2.5") — only history-kind VMs can anchor
        XCTAssertFalse(result.contains { entry in
            entry.reasons.contains(.versionAnchor(normalizedVersion: "0.2.5"))
        })
    }

    func test_longSession_timeFillEvenDistribution() {
        let history = (0..<20).map { "entry \($0)" }
        let result = MilestoneSampler.sample(history: history, versionMentions: [], K: 4)
        // With no version anchors, mandatory = {0, 19} after Phase 1.
        // Phase 3: slotsRemaining = K - 2 = 2, bucketWidth = historyCount / slotsRemaining = 20 / 2 = 10.
        // bucket 0 center = Int((0 + 0.5) * 10) = 5 → clamped to min(5, 19) = 5
        // bucket 1 center = Int((1 + 0.5) * 10) = 15 → clamped to min(15, 19) = 15
        // findNearestUnoccupied(5, occupied={0,19}) = 5 (unoccupied at center)
        // findNearestUnoccupied(15, occupied={0,19,5}) = 15
        // Final: {0, 5, 15, 19}
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.map { $0.index }), Set([0, 5, 15, 19]))
    }

    func test_mandatoryExceedsK_firstAndLastProtected() {
        // 5 version anchors + first + last = 7 mandatory, K = 4
        let history = (0..<20).map { "entry \($0)" }
        let vms = [2, 5, 8, 11, 14].map { idx in
            VersionMention(
                raw: "v0.\(idx).0", normalized: "0.\(idx).0",
                selectedSource: SourceRef(kind: .history, index: idx),
                occurrenceCount: 1
            )
        }
        let result = MilestoneSampler.sample(history: history, versionMentions: vms, K: 4)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.contains { $0.index == 0 })
        XCTAssertTrue(result.contains { $0.index == 19 })
    }

    func test_mandatoryExceedsK_priorityByOccurrence() {
        let history = (0..<20).map { "entry \($0)" }
        let vms = [
            VersionMention(raw: "v0.1.0", normalized: "0.1.0",
                           selectedSource: SourceRef(kind: .history, index: 5),
                           occurrenceCount: 1),
            VersionMention(raw: "v0.2.0", normalized: "0.2.0",
                           selectedSource: SourceRef(kind: .history, index: 10),
                           occurrenceCount: 5),
            VersionMention(raw: "v0.3.0", normalized: "0.3.0",
                           selectedSource: SourceRef(kind: .history, index: 15),
                           occurrenceCount: 2),
        ]
        // K=4, mandatory={0,19,5,10,15}=5 > K, truncate to 4.
        // Keep first/last + top 2 by occurrence: 0.2.0 (5) and 0.3.0 (2)
        let result = MilestoneSampler.sample(history: history, versionMentions: vms, K: 4)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.contains { $0.index == 10 })
        XCTAssertTrue(result.contains { $0.index == 15 })
        XCTAssertFalse(result.contains { $0.index == 5 })
    }

    func test_deterministicOutput_sameInputSameOutput() {
        let history = (0..<20).map { "entry \($0)" }
        let vms = [
            VersionMention(raw: "v0.2.5", normalized: "0.2.5",
                           selectedSource: SourceRef(kind: .history, index: 8),
                           occurrenceCount: 2),
        ]
        let a = MilestoneSampler.sample(history: history, versionMentions: vms, K: 4)
        let b = MilestoneSampler.sample(history: history, versionMentions: vms, K: 4)
        XCTAssertEqual(a, b)
    }

    func test_sortReasons_order_firstVersionLastTimeFill() {
        let history = (0..<5).map { "entry \($0)" }
        let vm = VersionMention(
            raw: "v0.2.5",
            normalized: "0.2.5",
            selectedSource: SourceRef(kind: .history, index: 0),
            occurrenceCount: 1
        )
        let result = MilestoneSampler.sample(history: history, versionMentions: [vm], K: 4)
        // First entry has firstEntry + versionAnchor; sort order: firstEntry, versionAnchor
        let firstEntry = result.first { $0.index == 0 }!
        XCTAssertEqual(firstEntry.reasons.count, 2)
        XCTAssertEqual(firstEntry.reasons[0], .firstEntry)
        XCTAssertEqual(firstEntry.reasons[1], .versionAnchor(normalizedVersion: "0.2.5"))
    }
}
