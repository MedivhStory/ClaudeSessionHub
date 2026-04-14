import Foundation

public struct MilestoneEntry: Sendable, Equatable {
    public let index: Int           // 0-based, into historyDisplayTexts
    public let totalCount: Int      // snapshot of historyDisplayTexts.count
    public let text: String         // historyDisplayTexts[index]
    public let reasons: [Reason]    // non-empty

    public enum Reason: Sendable, Equatable {
        case firstEntry
        case lastEntry
        case versionAnchor(normalizedVersion: String)
        case timeFill(bucket: Int, totalBuckets: Int)   // bucket is 0-based
    }

    public init(index: Int, totalCount: Int, text: String, reasons: [Reason]) {
        precondition(!reasons.isEmpty, "MilestoneEntry.reasons must be non-empty")
        self.index = index
        self.totalCount = totalCount
        self.text = text
        self.reasons = reasons
    }
}
