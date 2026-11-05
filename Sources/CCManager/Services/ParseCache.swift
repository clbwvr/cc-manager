import Foundation

/// On-disk cache of parsed session data, keyed by file path and validated by
/// (modification time, size). Parsing all JSONL transcripts on every launch is the
/// main startup cost (hundreds of MB); with this, only changed files are re-parsed.
struct CachedSession: Codable {
    var modified: Double        // file mtime as timeIntervalSince1970
    var size: Int               // file size in bytes
    var cwd: String
    var firstUserMessage: String
    var messageCount: Int
    var previews: [PreviewMessage]
    var searchableText: String
}

enum ParseCache {
    static let url: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/cc-manager-cache.json")

    static func load() -> [String: CachedSession] {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: CachedSession].self, from: data) else {
            return [:]
        }
        return cache
    }

    static func save(_ cache: [String: CachedSession]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
