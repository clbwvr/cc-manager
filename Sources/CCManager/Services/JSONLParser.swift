import Foundation

struct ParsedSession {
    var cwd: String
    var firstUserMessage: String
    var messageCount: Int
    var previews: [PreviewMessage]
    var searchableText: String
}

enum JSONLParser {
    /// Cap on per-session searchable text. Bounds resident memory and on-disk cache size;
    /// the big transcripts run to tens of MB and full-text search past this adds little.
    static let searchableCap = 200_000

    static func parse(at url: URL, previewLimit: Int = 12) -> ParsedSession? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var cwd = ""
        var firstUser = ""
        var count = 0
        var previews: [PreviewMessage] = []
        var searchable = ""
        // New-format fields (Claude Code v1.x+ no longer writes user/assistant lines)
        var aiTitle = ""
        var lastPrompts: [String] = []
        searchable.reserveCapacity(content.count / 2)

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            guard let type = obj["type"] as? String else { continue }

            if type == "ai-title" {
                if let t = obj["aiTitle"] as? String, !t.isEmpty { aiTitle = t }
                continue
            }
            if type == "last-prompt" {
                if let p = obj["lastPrompt"] as? String, !p.isEmpty { lastPrompts.append(p) }
                continue
            }

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
                if searchable.count < searchableCap {
                    searchable.append(text.lowercased())
                    searchable.append("\n")
                }
            }
        }

        // New format: no user/assistant lines but may have ai-title / last-prompt
        if count == 0 {
            guard !aiTitle.isEmpty || !lastPrompts.isEmpty else { return nil }
            let title = aiTitle.isEmpty ? (lastPrompts.last ?? "") : aiTitle
            let promptPreviews = lastPrompts.suffix(previewLimit).map { PreviewMessage(role: "user", text: $0) }
            let searchText = (lastPrompts + [aiTitle]).joined(separator: "\n").lowercased()
            return ParsedSession(
                cwd: cwd,
                firstUserMessage: title,
                messageCount: max(1, lastPrompts.count),
                previews: promptPreviews,
                searchableText: searchText
            )
        }

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
        var aiTitle = ""
        var lastPrompts: [String] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if type == "ai-title" {
                if let t = obj["aiTitle"] as? String, !t.isEmpty { aiTitle = t }
                continue
            }
            if type == "last-prompt" {
                if let p = obj["lastPrompt"] as? String, !p.isEmpty { lastPrompts.append(p) }
                continue
            }
            guard type == "user" || type == "assistant" else { continue }
            let isSidechain = (obj["isSidechain"] as? Bool) ?? false
            if isSidechain { continue }
            let msg = obj["message"] as? [String: Any]
            let text = extractText(from: msg?["content"])
            if text.isEmpty { continue }
            messages.append(PreviewMessage(role: type, text: text))
        }
        if messages.isEmpty {
            if !aiTitle.isEmpty {
                messages.append(PreviewMessage(role: "ai-title", text: aiTitle))
            }
            for p in lastPrompts {
                messages.append(PreviewMessage(role: "user", text: p))
            }
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
