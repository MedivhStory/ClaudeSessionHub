import Foundation

public enum VersionMentionExtractor {

    // Scan order is priority order. Decoupled from SourceKind declaration order
    // so enum reordering cannot silently change semantics.
    public static let scanOrder: [SourceKind] = [
        .taskSubject,
        .firstUserIntent,
        .lastUserIntent,
        .taskDescription,
        .history,
        .lastAssistantProgress
    ]

    private static let regex: NSRegularExpression = {
        let pattern = #"(?i)v?\d+\.\d+(\.\d+)?(-[A-Za-z0-9.]+)?"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    public static func extract(from signals: SessionSignals) -> [VersionMention] {
        // accumulator: normalized -> (raw, sourceRef, count)
        var accumulator: [String: (raw: String, sourceRef: SourceRef, count: Int)] = [:]

        for kind in scanOrder {
            let texts = textsFor(kind: kind, signals: signals)
            for (textIndex, text) in texts {
                guard let text = text, !text.isEmpty else { continue }
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, range: range)
                for match in matches {
                    guard let swiftRange = Range(match.range, in: text) else { continue }
                    let raw = String(text[swiftRange])
                    let normalized = normalize(raw)
                    if var existing = accumulator[normalized] {
                        existing.count += 1
                        accumulator[normalized] = existing
                    } else {
                        let sourceRef: SourceRef
                        if kind == .history {
                            sourceRef = SourceRef(kind: .history, index: textIndex)
                        } else {
                            sourceRef = SourceRef(kind: kind)
                        }
                        accumulator[normalized] = (raw: raw, sourceRef: sourceRef, count: 1)
                    }
                }
            }
        }

        let mentions = accumulator.map { (normalized, tuple) in
            VersionMention(
                raw: tuple.raw,
                normalized: normalized,
                selectedSource: tuple.sourceRef,
                occurrenceCount: tuple.count
            )
        }

        return mentions.sorted(by: compareMentions)
    }

    private static func textsFor(kind: SourceKind, signals: SessionSignals) -> [(Int, String?)] {
        switch kind {
        case .history:
            return signals.historyDisplayTexts.enumerated().map { ($0.offset, $0.element) }
        case .firstUserIntent:
            return [(0, signals.firstUserIntent)]
        case .lastUserIntent:
            return [(0, signals.lastUserIntent)]
        case .lastAssistantProgress:
            return [(0, signals.lastAssistantProgress)]
        case .taskSubject:
            return [(0, signals.taskSubject)]
        case .taskDescription:
            return [(0, signals.taskDescription)]
        }
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        if s.hasPrefix("v") { s.removeFirst() }
        return s
    }

    private static func compareMentions(_ a: VersionMention, _ b: VersionMention) -> Bool {
        let aPriority = scanOrder.firstIndex(of: a.selectedSource.kind) ?? Int.max
        let bPriority = scanOrder.firstIndex(of: b.selectedSource.kind) ?? Int.max
        if aPriority != bPriority { return aPriority < bPriority }
        if a.occurrenceCount != b.occurrenceCount { return a.occurrenceCount > b.occurrenceCount }
        return a.normalized < b.normalized
    }
}
