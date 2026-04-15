import Foundation

struct ProjectRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String = ""
    var knowledgeFiles: [String] = []
}

struct Metadata: Codable {
    var customTitles: [String: String] = [:]
    var bases: [String] = []
    var projects: [ProjectRecord] = []
    /// Maps conversation sessionId -> project id. Absent key = unassigned.
    var conversationProjects: [String: String] = [:]
}

enum MetadataStore {
    static let url: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/cc-manager.json")

    static func load() -> Metadata {
        guard let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Metadata.self, from: data) else {
            return Metadata()
        }
        return m
    }

    static func save(_ m: Metadata) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(m) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
