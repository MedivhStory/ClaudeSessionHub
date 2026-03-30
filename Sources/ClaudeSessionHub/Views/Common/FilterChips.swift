import SwiftUI

enum OverviewFilter: Hashable {
    case all
    case attention
    case active
    case agent(ProviderID)
    case recent7d

    var label: String {
        switch self {
        case .all: return "All"
        case .attention: return "Attention"
        case .active: return "Active"
        case .agent(let id): return id.capitalized
        case .recent7d: return "7d"
        }
    }
}

struct FilterChips: View {
    @Binding var selected: OverviewFilter
    let availableAgents: [ProviderID]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(for: .all)
                chip(for: .attention)
                chip(for: .active)
                ForEach(availableAgents.sorted(), id: \.self) { agent in
                    chip(for: .agent(agent))
                }
                chip(for: .recent7d)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func chip(for filter: OverviewFilter) -> some View {
        let isSelected = selected == filter
        return Button {
            selected = filter
        } label: {
            Text(filter.label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
