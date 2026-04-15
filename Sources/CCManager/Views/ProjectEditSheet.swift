import SwiftUI
import AppKit

struct ProjectEditSheet: View {
    @EnvironmentObject var store: ConversationStore
    @Environment(\.dismiss) private var dismiss

    let projectId: String

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var knowledgeFiles: [String] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Project").font(.headline)

            Group {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Project name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Knowledge files").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            addFiles()
                        } label: {
                            Label("Add Files…", systemImage: "plus")
                        }
                        .controlSize(.small)
                    }
                    KnowledgeFileList(files: $knowledgeFiles)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            guard !loaded, let p = store.project(id: projectId) else { return }
            name = p.name
            description = p.description
            knowledgeFiles = p.knowledgeFiles
            loaded = true
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path
                if !knowledgeFiles.contains(path) {
                    knowledgeFiles.append(path)
                }
            }
        }
    }

    private func save() {
        var record = store.project(id: projectId) ?? ProjectRecord(id: projectId, name: name)
        record.name = name
        record.description = description
        record.knowledgeFiles = knowledgeFiles
        store.updateProject(record)
        dismiss()
    }
}

private struct KnowledgeFileList: View {
    @Binding var files: [String]

    var body: some View {
        if files.isEmpty {
            Text("No files added.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(files, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            files.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxHeight: 140)
        }
    }
}
