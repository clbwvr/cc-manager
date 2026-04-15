import Foundation
import AppKit

@MainActor
final class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var projects: [ProjectRecord] = []

    private var metadata = MetadataStore.load() {
        didSet { projects = metadata.projects }
    }

    init() { projects = metadata.projects }

    private let projectsDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let dir = projectsDir
        let scanned: [Conversation] = await Task.detached(priority: .userInitiated) {
            Self.scan(projectsDir: dir)
        }.value

        self.conversations = scanned.map { applyMetadata($0) }
    }

    nonisolated private static func scan(projectsDir: URL) -> [Conversation] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var results: [Conversation] = []
        for dir in projectDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                guard let parsed = JSONLParser.parse(at: file) else { continue }
                let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let sessionId = file.deletingPathExtension().lastPathComponent
                results.append(Conversation(
                    sessionId: sessionId,
                    filePath: file,
                    cwd: parsed.cwd,
                    autoTitle: parsed.firstUserMessage,
                    customTitle: nil,
                    lastModified: mod,
                    messageCount: parsed.messageCount,
                    isBase: false,
                    projectId: nil,
                    previews: parsed.previews,
                    searchableText: parsed.searchableText
                ))
            }
        }
        return results.sorted { $0.lastModified > $1.lastModified }
    }

    private func applyMetadata(_ c: Conversation) -> Conversation {
        var copy = c
        copy.customTitle = metadata.customTitles[c.sessionId]
        copy.isBase = metadata.bases.contains(c.sessionId)
        copy.projectId = metadata.conversationProjects[c.sessionId]
        return copy
    }

    private func updateConversation(_ id: String, _ mutate: (inout Conversation) -> Void) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&conversations[idx])
    }

    // MARK: - Metadata mutations

    func toggleBase(_ c: Conversation) {
        if metadata.bases.contains(c.sessionId) {
            metadata.bases.removeAll { $0 == c.sessionId }
        } else {
            metadata.bases.append(c.sessionId)
        }
        MetadataStore.save(metadata)
        updateConversation(c.sessionId) { $0.isBase = metadata.bases.contains(c.sessionId) }
    }

    // MARK: - Projects

    @discardableResult
    func createProject(name: String) -> ProjectRecord {
        let record = ProjectRecord(id: UUID().uuidString.lowercased(), name: name)
        metadata.projects.append(record)
        MetadataStore.save(metadata)
        return record
    }

    func renameProject(_ id: String, to newName: String) {
        guard let idx = metadata.projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        metadata.projects[idx].name = trimmed
        MetadataStore.save(metadata)
    }

    func updateProject(_ record: ProjectRecord) {
        guard let idx = metadata.projects.firstIndex(where: { $0.id == record.id }) else { return }
        var updated = record
        updated.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        metadata.projects[idx] = updated
        MetadataStore.save(metadata)
    }

    func project(id: String) -> ProjectRecord? {
        metadata.projects.first { $0.id == id }
    }

    func deleteProject(_ id: String) {
        metadata.projects.removeAll { $0.id == id }
        for key in metadata.conversationProjects.keys where metadata.conversationProjects[key] == id {
            metadata.conversationProjects.removeValue(forKey: key)
        }
        MetadataStore.save(metadata)
        for i in conversations.indices where conversations[i].projectId == id {
            conversations[i].projectId = nil
        }
    }

    func setProject(for c: Conversation, to projectId: String?) {
        if let projectId {
            metadata.conversationProjects[c.sessionId] = projectId
        } else {
            metadata.conversationProjects.removeValue(forKey: c.sessionId)
        }
        MetadataStore.save(metadata)
        updateConversation(c.sessionId) { $0.projectId = projectId }
    }

    func rename(_ c: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            metadata.customTitles.removeValue(forKey: c.sessionId)
        } else {
            metadata.customTitles[c.sessionId] = trimmed
        }
        MetadataStore.save(metadata)
        updateConversation(c.sessionId) { $0.customTitle = trimmed.isEmpty ? nil : trimmed }
    }

    // MARK: - File mutations

    func delete(_ c: Conversation) {
        var trashedURL: NSURL?
        try? FileManager.default.trashItem(at: c.filePath, resultingItemURL: &trashedURL)
        // Also trash the companion folder (if any) named after the session id
        let companion = c.filePath.deletingPathExtension()
        if FileManager.default.fileExists(atPath: companion.path) {
            try? FileManager.default.trashItem(at: companion, resultingItemURL: nil)
        }
        // Clean up metadata
        metadata.customTitles.removeValue(forKey: c.sessionId)
        metadata.bases.removeAll { $0 == c.sessionId }
        MetadataStore.save(metadata)
        conversations.removeAll { $0.id == c.sessionId }
    }

    @discardableResult
    func fork(_ c: Conversation) -> Conversation? {
        let newId = UUID().uuidString.lowercased()
        let newURL = c.filePath
            .deletingLastPathComponent()
            .appendingPathComponent("\(newId).jsonl")
        do {
            try JSONLParser.rewriteSessionId(fileAt: c.filePath, to: newURL, newId: newId)
        } catch {
            errorMessage = "Fork failed: \(error.localizedDescription)"
            return nil
        }
        guard let parsed = JSONLParser.parse(at: newURL) else { return nil }
        let forkTitle = "Fork of \(c.title)"
        metadata.customTitles[newId] = forkTitle
        MetadataStore.save(metadata)

        let new = Conversation(
            sessionId: newId,
            filePath: newURL,
            cwd: parsed.cwd,
            autoTitle: parsed.firstUserMessage,
            customTitle: forkTitle,
            lastModified: Date(),
            messageCount: parsed.messageCount,
            isBase: false,
            projectId: nil,
            previews: parsed.previews,
            searchableText: parsed.searchableText
        )
        conversations.insert(new, at: 0)
        return new
    }

    // MARK: - Resume in iTerm2

    func resume(_ c: Conversation) {
        let cwd = c.cwd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : c.cwd
        launchITerm(cwd: cwd, sessionId: c.sessionId)
    }

    private func launchITerm(cwd: String, sessionId: String) {
        let escapedCwd = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedId = sessionId.replacingOccurrences(of: "\"", with: "\\\"")
        let cmd = "cd \"\(escapedCwd)\" && claude --resume \"\(escapedId)\""
        runITerm(shellCommand: cmd)
    }

    /// Launch a brand new Claude session, optionally pre-seeded with a slash command
    /// and/or a project's knowledge files (as `@path` references in the first message).
    func launchNewChat(
        cwd: String,
        slashCommand: String? = nil,
        knowledgeFiles: [String] = []
    ) {
        let path = cwd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : cwd
        let escapedCwd = path.replacingOccurrences(of: "\"", with: "\\\"")
        var cmd = "cd \"\(escapedCwd)\" && claude"

        // Build initial prompt from (slashCommand, knowledge files).
        var parts: [String] = []
        if let slash = slashCommand, !slash.isEmpty { parts.append(slash) }
        if !knowledgeFiles.isEmpty {
            let refs = knowledgeFiles.map { "@\($0)" }.joined(separator: " ")
            parts.append(refs)
        }
        if !parts.isEmpty {
            let prompt = parts.joined(separator: "\n")
            let escaped = prompt.replacingOccurrences(of: "\"", with: "\\\"")
            cmd += " \"\(escaped)\""
        }
        runITerm(shellCommand: cmd)
    }

    private func runITerm(shellCommand: String) {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let applescript = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(escaped)"
            end tell
        end tell
        """
        runAppleScript(applescript)
    }

    private func runAppleScript(_ source: String) {
        // Use /usr/bin/osascript via Process so the TCC prompt fires reliably and
        // we can capture stderr for diagnostics.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8) ?? "(no output)"
                errorMessage = """
                Failed to launch iTerm (exit \(process.terminationStatus)).

                \(msg)

                If this is a permissions issue, open System Settings → Privacy & Security → Automation and allow “cc-manager” to control iTerm.
                """
            }
        } catch {
            errorMessage = "Could not run osascript: \(error.localizedDescription)"
        }
    }

    // MARK: - Finder

    func revealInFinder(_ c: Conversation) {
        NSWorkspace.shared.activateFileViewerSelecting([c.filePath])
    }
}
