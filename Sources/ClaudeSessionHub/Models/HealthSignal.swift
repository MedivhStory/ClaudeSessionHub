import Foundation

enum HealthSignal: Sendable, Equatable {
    case stale(days: Int)
    case contextNearFull(percentage: Double, used: Int, limit: Int)
    case recentErrors(count: Int)

    var priority: Int {
        switch self {
        case .stale: return 1
        case .contextNearFull: return 2
        case .recentErrors: return 3
        }
    }
}
