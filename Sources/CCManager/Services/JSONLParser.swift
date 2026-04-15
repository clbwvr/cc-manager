import Foundation

struct ParsedSession {
    var cwd: String
    var firstUserMessage: String
    var messageCount: Int
    var previews: [PreviewMessage]
    var searchableText: String
}

enum JSONLParser {
    static func parse(at url: URL, previewLimit: Int = 12) -> ParsedSession? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var cwd = ""
        var firstUser = ""
        var count = 0
        var previews: [PreviewMessage] = []
        var searchable = ""
        searchable.reserveCapacity(content.count / 2)

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            guard let type = obj["type"] as? String else { continue }
            if type != "user" && type != "assistant" { continue }

            let isSidechain = (obj["isSidechain"] as? Bool) ?? false
            if cwd.isEmpty, let c = obj["cwd"] as? String { cwd = c }

            let msg = obj["message"] as? [String: Any]
            let text = extractText(from: msg?["content"])

            if !isSidechain && !text.isEmpty {
                count += 1
                if type == "user" && firstUser.isEmpty && !looksLikeToolResult(msg?["content"]) {
                    firstUser = text
                }
                if previews.count < previewLimit {
                    previews.append(PreviewMessage(role: type, text: text))
                }
                searchable.append(text.lowercased())
                searchable.append("\n")
            }
        }

        guard count > 0 else { return nil }
        return ParsedSession(
            cwd: cwd,
            firstUserMessage: firstUser,
            messageCount: count,
            previews: previews,
            searchableText: searchable
        )
    }

    private static func extractText(from content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            let parts: [String] = arr.compactMap { block in
                if let t = block["text"] as? String { return t }
                return nil
            }
            return parts.joined(separator: "\n")
        }
        return ""
    }

    private static func looksLikeToolResult(_ content: Any?) -> Bool {
        guard let arr = content as? [[String: Any]] else { return false }
        return arr.contains { ($0["type"] as? String) == "tool_result" }
    }

    /// Load every user/assistant message from a session file (non-sidechain).
    static func loadAllMessages(at url: URL) -> [PreviewMessage] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var messages: [PreviewMessage] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String,
                  type == "user" || type == "assistant" else { continue }
            let isSidechain = (obj["isSidechain"] as? Bool) ?? false
            if isSidechain { continue }
            let msg = obj["message"] as? [String: Any]
            let text = extractText(from: msg?["content"])
            if text.isEmpty { continue }
            messages.append(PreviewMessage(role: type, text: text))
        }
        return messages
    }

    /// Rewrite every `sessionId` field in the JSONL to a new id (used for forks).
    static func rewriteSessionId(fileAt src: URL, to dst: URL, newId: String) throws {
        let content = try String(contentsOf: src, encoding: .utf8)
        var out = ""
        out.reserveCapacity(content.count)
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                out.append("\n")
                continue
            }
            if let data = line.data(using: .utf8),
               var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if obj["sessionId"] != nil {
                    obj["sessionId"] = newId
                }
                if let newData = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]),
                   let s = String(data: newData, encoding: .utf8) {
                    out.append(s)
                    out.append("\n")
                    continue
                }
            }
            out.append(String(line))
            out.append("\n")
        }
        try out.write(to: dst, atomically: true, encoding: .utf8)
    }
}
