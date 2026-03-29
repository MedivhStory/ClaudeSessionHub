import Foundation

public enum HealthEngine {
    public static func computeSignals(for session: SessionSummary) -> [HealthSignal] {
        var candidates: [HealthSignal] = []

        // Signal 1: Stale (priority 1)
        // Trigger: stopped AND not done AND inactive >= 2 days
        if session.runtimeState == .stopped && session.taskPhase != .done {
            let daysSinceActive = Calendar.current.dateComponents(
                [.day], from: session.lastActiveAt, to: Date()
            ).day ?? 0
            if daysSinceActive >= 2 {
                candidates.append(.stale(days: daysSinceActive))
            }
        }

        // Signal 2: Context near full (priority 2)
        // Trigger: contextUsage percentage >= 75%
        if let usage = session.contextUsage, usage.percentage >= 0.75 {
            candidates.append(.contextNearFull(
                percentage: usage.percentage,
                used: usage.promptContext,
                limit: usage.limit
            ))
        }

        // Signal 3: Recent errors (priority 3)
        // Trigger: recentErrorCount >= 1
        if session.recentErrorCount >= 1 {
            candidates.append(.recentErrors(count: session.recentErrorCount))
        }

        // Sort by priority ascending, take max 2
        return Array(candidates.sorted { $0.priority < $1.priority }.prefix(2))
    }
}
