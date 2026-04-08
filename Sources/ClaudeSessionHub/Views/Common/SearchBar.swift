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
    /// Returns true if the session matches the search query using weighted scoring.
    static func matches(_ session: SessionSummary, query: String, store: SessionStore) -> Bool {
        guard !query.isEmpty else { return true }
        let sid = session.ref.sessionID
        return SearchScorer.score(
            query: query,
            title: session.title,
            smartTitle: store.titleStore.currentTitle(for: sid)?.text,
            taskSummary: session.currentTaskSummary,
            progress: store.titleStore.lastProgress(for: sid),
            userNote: store.titleStore.userNote(for: sid),
            branch: session.branch,
            cwd: session.cwd,
            sessionID: sid,
            historyTexts: store.cachedHistoryTexts(for: sid)
        ) > 0
    }
}
