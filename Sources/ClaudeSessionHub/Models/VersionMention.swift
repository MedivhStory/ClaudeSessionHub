import Foundation

public struct VersionMention: Sendable, Codable, Equatable {
    public let raw: String           // original match, preserving case and prefix: "V0.2.5", "v0.2.5", "0.2.5"
    public let normalized: String    // lowercase, leading 'v' stripped: "0.2.5"
    public let selectedSource: SourceRef
    public let occurrenceCount: Int

    public init(
        raw: String,
        normalized: String,
        selectedSource: SourceRef,
        occurrenceCount: Int
    ) {
        self.raw = raw
        self.normalized = normalized
        self.selectedSource = selectedSource
        self.occurrenceCount = occurrenceCount
    }
}

public struct SourceRef: Sendable, Codable, Equatable {
    public let kind: SourceKind
    public let index: Int?    // 0-based; non-nil iff kind == .history

    public init(kind: SourceKind, index: Int? = nil) {
        // Invariant: .history requires non-nil index; other kinds require nil.
        precondition(
            (kind == .history && index != nil) || (kind != .history && index == nil),
            "SourceRef invariant: .history requires non-nil index; other kinds require nil index. kind=\(kind), index=\(String(describing: index))"
        )
        self.kind = kind
        self.index = index
    }

    // Custom decoder rejects the two invalid combinations instead of relying on
    // downstream code to skip malformed entries.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SourceKind.self, forKey: .kind)
        let index = try container.decodeIfPresent(Int.self, forKey: .index)
        if kind == .history && index == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .index, in: container,
                debugDescription: "SourceRef with kind=.history must have a non-nil 0-based index"
            )
        }
        if kind != .history && index != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .index, in: container,
                debugDescription: "SourceRef with kind=\(kind) must have index=null"
            )
        }
        self.kind = kind
        self.index = index
    }

    private enum CodingKeys: String, CodingKey {
        case kind, index
    }
}

public enum SourceKind: String, Sendable, Codable, CaseIterable {
    case history
    case firstUserIntent
    case lastUserIntent
    case lastAssistantProgress
    case taskSubject
    case taskDescription
}
