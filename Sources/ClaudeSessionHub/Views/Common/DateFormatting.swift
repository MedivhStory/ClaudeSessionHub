import Foundation

extension Date {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Abbreviated relative time string (e.g. "2m ago", "3h ago").
    var relativeFormatted: String {
        Self.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
}
