import Foundation

struct PreviewMessage: Hashable {
    let role: String
    let text: String
}

struct Conversation: Identifiable, Hashable {
    let sessionId: String
    let filePath: URL
    let cwd: String
    let autoTitle: String
    var customTitle: String?
    var lastModified: Date
    var messageCount: Int
    var isBase: Bool
    var projectId: String?
    var previews: [PreviewMessage]
    var searchableText: String

    var id: String { sessionId }
    var title: String {
        let t = customTitle ?? autoTitle
        return t.isEmpty ? "(untitled)" : t
    }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
