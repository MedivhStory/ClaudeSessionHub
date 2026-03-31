import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search sessions..."
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand {
                    text = ""
                    isFocused.wrappedValue = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Search Filtering

extension SearchBar {
    /// Returns true if the session matches the search query (case-insensitive).
    static func matches(_ session: SessionSummary, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        let fields: [String?] = [
            session.title,
            session.currentTaskSummary,
            session.cwd,
            session.ref.sessionID,
            session.branch
        ]
        return fields.contains { $0?.lowercased().contains(q) == true }
    }
}
