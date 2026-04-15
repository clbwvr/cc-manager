import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var store: ConversationStore
    let filter: SidebarFilter
    @Binding var search: String
    @Binding var selectedIds: Set<String>

    @State private var renameTarget: Conversation?
    @State private var deleteTargets: [Conversation] = []
    @State private var showDeleteConfirm = false
    @State private var newProjectForTargets: [Conversation]?

    var body: some View {
        List(selection: $selectedIds) {
            ForEach(filtered) { c in
                ConversationRow(conversation: c)
                    .tag(c.id)
                    .contextMenu { contextMenu(for: c) }
                    .draggable(dragPayload(for: c))
            }
        }
        .background {
            // Invisible buttons that carry keyboard shortcuts for the selected conversation(s).
            Group {
                Button("") { resumeSelected() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(singleSelection == nil)
                Button("") { forkSelected() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(singleSelection == nil)
                Button("") { renameSelected() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(singleSelection == nil)
                Button("") { toggleBaseSelected() }
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(selectedConversations.isEmpty)
                Button("") { deleteSelectedRequest() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selectedConversations.isEmpty)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search title, path, or message content")
        .overlay {
            if store.isLoading && store.conversations.isEmpty {
                ProgressView("Scanning conversations…")
            } else if filtered.isEmpty {
                ContentUnavailableView.search
            }
        }
        .sheet(item: $renameTarget) { c in
            TextPromptSheet(
                title: "Rename Conversation",
                placeholder: "Title",
                initial: c.title
            ) { newTitle in
                store.rename(c, to: newTitle)
                renameTarget = nil
            } onCancel: {
                renameTarget = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { newProjectForTargets != nil },
            set: { if !$0 { newProjectForTargets = nil } }
        )) {
            TextPromptSheet(
                title: "New Project",
                placeholder: "Project name",
                initial: "",
                confirmLabel: "Create & Assign"
            ) { name in
                let record = store.createProject(name: name)
                for c in newProjectForTargets ?? [] {
                    store.setProject(for: c, to: record.id)
                }
                newProjectForTargets = nil
            } onCancel: {
                newProjectForTargets = nil
            }
        }
        .confirmationDialog(
            deleteTargets.count == 1
                ? "Delete conversation?"
                : "Delete \(deleteTargets.count) conversations?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Move to Trash", role: .destructive) {
                for c in deleteTargets {
                    store.delete(c)
                    selectedIds.remove(c.id)
                }
                deleteTargets = []
            }
            Button("Cancel", role: .cancel) { deleteTargets = [] }
        } message: {
            if deleteTargets.count == 1 {
                Text("“\(deleteTargets[0].title)” will be moved to Trash.")
            } else {
                Text("These will be moved to Trash.")
            }
        }
    }

    /// Context-menu target follows macOS convention: if the right-clicked row
    /// is part of the current selection, act on all selected; otherwise act on just that row.
    private var selectedConversations: [Conversation] {
        store.conversations.filter { selectedIds.contains($0.id) }
    }

    private var singleSelection: Conversation? {
        selectedConversations.count == 1 ? selectedConversations.first : nil
    }

    private func resumeSelected() {
        guard let c = singleSelection else { return }
        store.resume(c)
    }

    private func forkSelected() {
        guard let c = singleSelection else { return }
        if let forked = store.fork(c) { selectedIds = [forked.id] }
    }

    private func renameSelected() {
        guard let c = singleSelection else { return }
        renameTarget = c
    }

    private func toggleBaseSelected() {
        let targets = selectedConversations
        guard !targets.isEmpty else { return }
        for t in targets { store.toggleBase(t) }
    }

    private func deleteSelectedRequest() {
        let targets = selectedConversations
        guard !targets.isEmpty else { return }
        deleteTargets = targets
        showDeleteConfirm = true
    }

    private func dragPayload(for c: Conversation) -> ConversationDragPayload {
        if selectedIds.contains(c.id) {
            return ConversationDragPayload(sessionIds: Array(selectedIds))
        }
        return ConversationDragPayload(sessionIds: [c.id])
    }

    private func targets(for c: Conversation) -> [Conversation] {
        if selectedIds.contains(c.id) {
            return store.conversations.filter { selectedIds.contains($0.id) }
        }
        return [c]
    }

    @ViewBuilder
    private func contextMenu(for c: Conversation) -> some View {
        let targets = targets(for: c)
        let isSingle = targets.count == 1

        if isSingle {
            Button("Resume in iTerm2") { store.resume(c) }
            Button("Fork") {
                if let forked = store.fork(c) {
                    selectedIds = [forked.id]
                }
            }
            Divider()
        }

        Menu("Move to Project") {
            Button("None (Unassigned)") {
                for t in targets { store.setProject(for: t, to: nil) }
            }
            if !store.projects.isEmpty {
                Divider()
                ForEach(store.projects) { proj in
                    Button(proj.name) {
                        for t in targets { store.setProject(for: t, to: proj.id) }
                    }
                }
            }
            Divider()
            Button("New Project…") {
                newProjectForTargets = targets
            }
        }

        Button(allBases(targets) ? "Unmark Base" : "Mark as Base") {
            for t in targets { store.toggleBase(t) }
        }

        if isSingle {
            Button("Rename…") { renameTarget = c }
        }

        Divider()
        if isSingle {
            Button("Reveal in Finder") { store.revealInFinder(c) }
            Divider()
        }

        Button(
            isSingle ? "Delete…" : "Delete \(targets.count)…",
            role: .destructive
        ) {
            deleteTargets = targets
            showDeleteConfirm = true
        }
    }

    private func allBases(_ items: [Conversation]) -> Bool {
        !items.isEmpty && items.allSatisfy(\.isBase)
    }

    private var filtered: [Conversation] {
        var items = store.conversations
        switch filter {
        case .all: break
        case .bases: items = items.filter(\.isBase)
        case .unassigned: items = items.filter { $0.projectId == nil }
        case .project(let id): items = items.filter { $0.projectId == id }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q)
                    || $0.cwd.lowercased().contains(q)
                    || $0.searchableText.contains(q)
            }
        }
        return items
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: conversation.isBase ? "star.fill" : "bubble.left")
                .foregroundStyle(conversation.isBase ? .yellow : .secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(conversation.projectName.isEmpty ? "—" : conversation.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(conversation.messageCount) msgs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary)
                    Text(conversation.lastModified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

