import SwiftUI

struct HeatStripView: View {
    let projects: [String: [SessionSummary]]
    var onSelectProject: ((String) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedProjectNames, id: \.self) { name in
                    projectBlock(name: name, sessions: projects[name] ?? [])
                        .onTapGesture {
                            onSelectProject?(name)
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private var sortedProjectNames: [String] {
        projects.keys.sorted { lhs, rhs in
            let lActive = projects[lhs]?.filter { $0.runtimeState == .active }.count ?? 0
            let rActive = projects[rhs]?.filter { $0.runtimeState == .active }.count ?? 0
            if lActive != rActive { return lActive > rActive }
            return lhs < rhs
        }
    }

    private func projectBlock(name: String, sessions: [SessionSummary]) -> some View {
        let activeCount = sessions.filter { $0.runtimeState == .active }.count
        let attentionCount = sessions.filter { !HealthEngine.computeSignals(for: $0).isEmpty }.count

        return HStack(spacing: 3) {
            Text(name)
                .font(.caption)
                .lineLimit(1)

            if activeCount > 0 {
                ForEach(0..<min(activeCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            if attentionCount > 0 {
                ForEach(0..<min(attentionCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
