import SwiftUI
import AppKit

struct NewChatSheet: View {
    @EnvironmentObject var store: ConversationStore
    @Environment(\.dismiss) private var dismiss

    @State private var cwd: String = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var selectedSkill: Skill?
    @State private var skills: [Skill] = []
    @State private var selectedProjectId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Claude Conversation").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Working directory").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField("~", text: $cwd)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { pickDirectory() }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Project (optional)").font(.subheadline).foregroundStyle(.secondary)
                Picker("Project", selection: $selectedProjectId) {
                    Text("None").tag(String?.none)
                    ForEach(store.projects) { proj in
                        Text(proj.name).tag(Optional(proj.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if let pid = selectedProjectId, let p = store.project(id: pid) {
                    if !p.description.isEmpty {
                        Text(p.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    if !p.knowledgeFiles.isEmpty {
                        Text("\(p.knowledgeFiles.count) knowledge file(s) will be included")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Start with a skill (optional)").font(.subheadline).foregroundStyle(.secondary)
                Picker("Skill", selection: $selectedSkill) {
                    Text("None").tag(Skill?.none)
                    ForEach(skills) { skill in
                        Text("/\(skill.name)  —  \(skill.kind.rawValue)")
                            .tag(Optional(skill))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if let skill = selectedSkill, !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Start") {
                    let files = selectedProjectId.flatMap { store.project(id: $0)?.knowledgeFiles } ?? []
                    store.launchNewChat(
                        cwd: cwd,
                        slashCommand: selectedSkill?.slashCommand,
                        knowledgeFiles: files
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440)
        .onAppear { skills = SkillStore.load() }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cwd)
        if panel.runModal() == .OK, let url = panel.url {
            cwd = url.path
        }
    }
}
