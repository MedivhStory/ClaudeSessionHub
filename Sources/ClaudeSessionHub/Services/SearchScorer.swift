import Foundation

/// Weighted content-first search scoring for sessions.
public enum SearchScorer {

    public struct MatchEvidence: Sendable {
        public let field: String
        public let snippet: String
    }

    public static func score(
        query: String,
        title: String,
        smartTitle: String?,
        taskSummary: String?,
        progress: String?,
        userNote: String?,
        branch: String?,
        cwd: String?,
        sessionID: String,
        historyTexts: [String]
    ) -> Double {
        guard !query.isEmpty else { return 1.0 }
        let q = query.lowercased()
        var total: Double = 0

        let fields: [(String?, Double)] = [
            (smartTitle, 10.0),
            (userNote, 9.0),
            (title, 8.0),
            (taskSummary, 7.0),
            (progress, 6.0),
            (branch, 4.0),
            (cwd, 3.0),
            (sessionID, 1.0)
        ]

        for (field, weight) in fields {
            if let f = field?.lowercased(), f.contains(q) {
                total += weight
            }
        }

        for text in historyTexts {
            if text.lowercased().contains(q) {
                total += 5.0
                break
            }
        }

        return total
    }

    public static func matchEvidence(
        query: String,
        title: String,
        smartTitle: String?,
        taskSummary: String?,
        progress: String?,
        userNote: String?,
        branch: String?,
        cwd: String?,
        sessionID: String,
        historyTexts: [String]
    ) -> [MatchEvidence] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        var evidence: [MatchEvidence] = []

        let namedFields: [(String, String?)] = [
            ("smartTitle", smartTitle),
            ("title", title),
            ("userNote", userNote),
            ("taskSummary", taskSummary),
            ("progress", progress),
            ("branch", branch),
            ("cwd", cwd)
        ]

        for (name, value) in namedFields {
            if let v = value, v.lowercased().contains(q) {
                evidence.append(MatchEvidence(field: name, snippet: truncateAround(v, query: q, radius: 30)))
            }
        }

        for text in historyTexts {
            if text.lowercased().contains(q) {
                evidence.append(MatchEvidence(field: "history", snippet: truncateAround(text, query: q, radius: 30)))
                break
            }
        }

        return evidence
    }

    private static func truncateAround(_ text: String, query: String, radius: Int) -> String {
        guard let range = text.lowercased().range(of: query) else { return String(text.prefix(60)) }
        let center = text.distance(from: text.startIndex, to: range.lowerBound)
        let start = max(0, center - radius)
        let end = min(text.count, center + query.count + radius)
        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(text.startIndex, offsetBy: end)
        var snippet = String(text[startIdx..<endIdx])
        if start > 0 { snippet = "…" + snippet }
        if end < text.count { snippet = snippet + "…" }
        return snippet
    }
}
