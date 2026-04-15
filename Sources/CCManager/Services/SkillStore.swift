import Foundation

struct Skill: Identifiable, Hashable {
    let name: String        // slash command name, e.g. "morning"
    let kind: Kind
    let path: URL
    let description: String // first heading/line from the file

    enum Kind: String { case skill, command }

    var id: String { "\(kind.rawValue):\(name)" }
    var slashCommand: String { "/\(name)" }
}

enum SkillStore {
    private static let skillsDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills")

    private static let commandsDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/commands")

    static func load() -> [Skill] {
        var out: [Skill] = []
        out.append(contentsOf: scanSkills())
        out.append(contentsOf: scanCommands())
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func scanSkills() -> [Skill] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.compactMap { dir in
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { return nil }
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { return nil }
            return Skill(
                name: dir.lastPathComponent,
                kind: .skill,
                path: skillFile,
                description: firstMeaningfulLine(skillFile) ?? ""
            )
        }
    }

    private static func scanCommands() -> [Skill] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: commandsDir, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { file in
            guard file.pathExtension == "md" else { return nil }
            return Skill(
                name: file.deletingPathExtension().lastPathComponent,
                kind: .command,
                path: file,
                description: firstMeaningfulLine(file) ?? ""
            )
        }
    }

    /// Grab the first non-empty non-frontmatter line as a short description.
    private static func firstMeaningfulLine(_ url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inFrontmatter = false
        var sawFrontmatterStart = false
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line == "---" {
                if !sawFrontmatterStart {
                    sawFrontmatterStart = true
                    inFrontmatter = true
                } else {
                    inFrontmatter = false
                }
                continue
            }
            if inFrontmatter {
                if line.lowercased().hasPrefix("description:") {
                    return String(line.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if line.isEmpty { continue }
            let cleaned = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }
}
