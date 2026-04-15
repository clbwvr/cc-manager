import SwiftUI

enum SidebarFilter: Hashable {
    case all
    case bases
    case unassigned
    case project(String) // projectId
}

struct ContentView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var filter: SidebarFilter? = .all
    @State private var selectedIds: Set<String> = []
    @State private var search: String = ""
    @State private var showNewChat = false

    var body: some View {
        NavigationSplitView {
            SidebarView(filter: $filter)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            ConversationListView(
                filter: filter ?? .all,
                search: $search,
                selectedIds: $selectedIds
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 420)
        } detail: {
            detailPane
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewChat = true
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Start a new Claude conversation (⌘N)")
            }
        }
        .sheet(isPresented: $showNewChat) {
            NewChatSheet()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            ),
            presenting: store.errorMessage
        ) { _ in
            Button("OK") { store.errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        let selected = store.conversations.filter { selectedIds.contains($0.id) }
        if selected.count == 1, let convo = selected.first {
            ConversationDetailView(conversation: convo)
        } else if selected.count > 1 {
            MultiSelectionView(conversations: selected) { selectedIds.removeAll() }
        } else {
            ContentUnavailableView(
                "No conversation selected",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Pick a conversation from the list")
            )
        }
    }
}
