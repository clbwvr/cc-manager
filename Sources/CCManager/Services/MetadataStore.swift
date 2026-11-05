import Foundation

enum ProjectStatus: String, Codable, CaseIterable, Hashable {
    case active
    case todo
    case complete
}

struct ProjectRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String = ""
    var knowledgeFiles: [String] = []
    var status: ProjectStatus = .active

    init(id: String, name: String, description: String = "", knowledgeFiles: [String] = [], status: ProjectStatus = .active) {
        self.id = id
        self.name = name
        self.description = description
        self.knowledgeFiles = knowledgeFiles
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        knowledgeFiles = try container.decodeIfPresent([String].self, forKey: .knowledgeFiles) ?? []
        status = try container.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .active
    }
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
