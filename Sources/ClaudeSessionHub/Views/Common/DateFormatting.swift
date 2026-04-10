import Foundation

extension Date {
    /// Abbreviated relative time string (e.g. "2m ago", "3h ago").
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
