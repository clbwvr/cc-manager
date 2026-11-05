import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: ConversationStore
    @Binding var filter: SidebarFilter?

    @State private var newProjectSheet = false
    @State private var renameProject: ProjectRecord?
    @State private var editProjectId: String?
    @State private var deleteProjectId: String?
    @State private var showTodo = true
    @State private var showComplete = false

    var body: some View {
        List(selection: $filter) {
            Section {
                ForEach(topItems) { item in
                    Label(item.title, systemImage: item.icon)
                        .foregroundStyle(item.tint)
                        .badge(item.count)
                        .modifier(DropToUnassignedModifier(filter: item.filter))
                }
            }

            Section {
                ForEach(projectItems(for: .active)) { item in
                    projectRow(item)
                }
            } header: {
                HStack {
                    Text("Active")
                    Spacer()
                    Button {
                        newProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New project")
                }
            }

            if !projectItems(for: .todo).isEmpty {
                Section(isExpanded: $showTodo) {
                    ForEach(projectItems(for: .todo)) { item in
                        projectRow(item)
                    }
                } header: {
                    Text("Todo")
                }
            }

            if !projectItems(for: .complete).isEmpty {
                Section(isExpanded: $showComplete) {
                    ForEach(projectItems(for: .complete)) { item in
                        projectRow(item)
                    }
                } header: {
                    Text("Complete")
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $newProjectSheet) {
            TextPromptSheet(
                title: "New Project",
                placeholder: "Project name",
                initial: "",
                confirmLabel: "Create"
            ) { name in
                let record = store.createProject(name: name)
                filter = .project(record.id)
                newProjectSheet = false
            } onCancel: {
                newProjectSheet = false
            }
        }
        .sheet(isPresented: Binding(
            get: { editProjectId != nil },
            set: { if !$0 { editProjectId = nil } }
        )) {
            if let id = editProjectId {
                ProjectEditSheet(projectId: id)
            }
        }
        .sheet(item: $renameProject) { proj in
            TextPromptSheet(
                title: "Rename Project",
                placeholder: "Project name",
                initial: proj.name,
                confirmLabel: "Save"
            ) { newName in
                store.renameProject(proj.id, to: newName)
                renameProject = nil
            } onCancel: {
                renameProject = nil
            }
        }
        .confirmationDialog(
            "Delete project?",
            isPresented: Binding(
                get: { deleteProjectId != nil },
                set: { if !$0 { deleteProjectId = nil } }
            ),
            presenting: deleteProjectId
        ) { id in
            Button("Delete", role: .destructive) {
                if filter == .project(id) { filter = .all }
                store.deleteProject(id)
                deleteProjectId = nil
            }
            Button("Cancel", role: .cancel) { deleteProjectId = nil }
        } message: { _ in
            Text("Conversations in this project will become unassigned. The conversations themselves are not deleted.")
        }
    }

    @ViewBuilder
    private func projectRow(_ item: ProjectItem) -> some View {
        let icon: String = switch item.status {
        case .active: "folder.fill"
        case .todo: "folder.badge.questionmark"
        case .complete: "folder.badge.checkmark"
        }
        Label(item.name, systemImage: icon)
            .badge(item.count)
            .contextMenu {
                Button("Edit…") {
                    editProjectId = item.id.projectId
                }
                Button("Rename…") {
                    renameProject = ProjectRecord(id: item.id.projectId ?? "", name: item.name)
                }
                Divider()
                Menu("Move to") {
                    ForEach(ProjectStatus.allCases, id: \.self) { status in
                        if status != item.status {
                            Button(status.rawValue.capitalized) {
                                if let pid = item.projectId { store.setProjectStatus(pid, status: status) }
                            }
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    deleteProjectId = item.id.projectId
                }
            }
            .help(projectHelp(for: item))
            .dropDestination(for: ConversationDragPayload.self) { payloads, _ in
                handleDrop(payloads: payloads, projectId: item.projectId)
            }
    }

    private func projectHelp(for item: ProjectItem) -> String {
        guard let pid = item.projectId, let p = store.project(id: pid) else { return "" }
        var parts: [String] = []
        if !p.description.isEmpty { parts.append(p.description) }
        if !p.knowledgeFiles.isEmpty { parts.append("\(p.knowledgeFiles.count) knowledge file(s)") }
        return parts.joined(separator: "\n")
    }

    // MARK: - Drop handling

    private func handleDrop(payloads: [ConversationDragPayload], projectId: String?) -> Bool {
        let ids = payloads.flatMap { $0.sessionIds }
        guard !ids.isEmpty else { return false }
        for id in ids {
            if let c = store.conversations.first(where: { $0.id == id }) {
                store.setProject(for: c, to: projectId)
            }
        }
        return true
    }

    /// Applies a drop destination only to the Unassigned row, so dragging onto All/Bases is a no-op.
    private struct DropToUnassignedModifier: ViewModifier {
        @EnvironmentObject var store: ConversationStore
        let filter: SidebarFilter

        func body(content: Content) -> some View {
            if case .unassigned = filter {
                content.dropDestination(for: ConversationDragPayload.self) { payloads, _ in
                    let ids = payloads.flatMap { $0.sessionIds }
                    for id in ids {
                        if let c = store.conversations.first(where: { $0.id == id }) {
                            store.setProject(for: c, to: nil)
                        }
                    }
                    return true
                }
            } else {
                content
            }
        }
    }

    // MARK: - Data

    private struct TopItem: Identifiable {
        let filter: SidebarFilter
        let title: String
        let icon: String
        let count: Int
        let tint: Color
        var id: SidebarFilter { filter }
    }

    private struct ProjectItem: Identifiable {
        let id: SidebarFilter
        let name: String
        let count: Int
        let status: ProjectStatus
        var projectId: String? {
            if case .project(let pid) = id { return pid }
            return nil
        }
    }

    private var topItems: [TopItem] {
        let all = store.conversations.count
        let bases = store.conversations.filter(\.isBase).count
        let unassigned = store.conversations.filter { $0.projectId == nil }.count
        return [
            TopItem(filter: .all, title: "All", icon: "tray.full", count: all, tint: .primary),
            TopItem(filter: .bases, title: "Bases", icon: "star.fill", count: bases, tint: .yellow),
            TopItem(filter: .unassigned, title: "Unassigned", icon: "tray", count: unassigned, tint: .secondary)
        ]
    }

    private func projectItems(for status: ProjectStatus) -> [ProjectItem] {
        store.projects.filter { $0.status == status }.map { proj in
            let count = store.conversations.filter { $0.projectId == proj.id }.count
            return ProjectItem(id: .project(proj.id), name: proj.name, count: count, status: proj.status)
        }
    }
}

// Convenience for SidebarFilter Identifiable-ish access used above
extension SidebarFilter {
    var projectId: String? {
        if case .project(let id) = self { return id }
        return nil
    }
}
