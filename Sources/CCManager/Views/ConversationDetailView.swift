import SwiftUI

struct ConversationDetailView: View {
    @EnvironmentObject var store: ConversationStore
    let conversation: Conversation

    @State private var messages: [PreviewMessage] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
                .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        ProgressView().padding()
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                        MessageBubble(message: msg)
                    }
                    if !isLoading && messages.isEmpty {
                        Text("No messages.").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .task(id: conversation.id) {
            await loadMessages()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.resume(conversation)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .help("Open in iTerm2 and resume")

                Button {
                    _ = store.fork(conversation)
                } label: {
                    Label("Fork", systemImage: "arrow.triangle.branch")
                }

                Button {
                    store.toggleBase(conversation)
                } label: {
                    Label(
                        conversation.isBase ? "Unmark Base" : "Mark Base",
                        systemImage: conversation.isBase ? "star.fill" : "star"
                    )
                    .foregroundStyle(conversation.isBase ? .yellow : .primary)
                }
            }
        }
    }

    private func loadMessages() async {
        isLoading = true
        messages = []
        let url = conversation.filePath
        let loaded = await Task.detached(priority: .userInitiated) {
            JSONLParser.loadAllMessages(at: url)
        }.value
        messages = loaded
        isLoading = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if conversation.isBase {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                Text(conversation.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Label(conversation.cwd.isEmpty ? "—" : conversation.cwd, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("·").foregroundStyle(.secondary)
                Text("\(conversation.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(conversation.lastModified, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(conversation.sessionId)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageBubble: View {
    let message: PreviewMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == "ai-title" ? "Title" : message.role.capitalized)
                .font(.caption.bold())
                .foregroundStyle(message.role == "user" ? .blue : .purple)
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
    }
}
