// Tests/XCTests/Models/MilestoneEntryTests.swift
import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class MilestoneEntryTests: XCTestCase {
    func test_init_withNonEmptyReasons_succeeds() {
        let entry = MilestoneEntry(
            index: 0,
            totalCount: 10,
            text: "hello",
            reasons: [.firstEntry]
        )
        XCTAssertEqual(entry.reasons.count, 1)
        XCTAssertEqual(entry.reasons.first, .firstEntry)
    }

    func test_reason_versionAnchor_equality() {
        let a = MilestoneEntry.Reason.versionAnchor(normalizedVersion: "0.2.5")
        let b = MilestoneEntry.Reason.versionAnchor(normalizedVersion: "0.2.5")
        let c = MilestoneEntry.Reason.versionAnchor(normalizedVersion: "0.2.6")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_reason_timeFill_equality() {
        XCTAssertEqual(
            MilestoneEntry.Reason.timeFill(bucket: 2, totalBuckets: 5),
            MilestoneEntry.Reason.timeFill(bucket: 2, totalBuckets: 5)
        )
    }
}
