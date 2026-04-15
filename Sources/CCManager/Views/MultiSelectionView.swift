import SwiftUI

struct MultiSelectionView: View {
    @EnvironmentObject var store: ConversationStore
    let conversations: [Conversation]
    let onClear: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("\(conversations.count) conversations selected")
                .font(.title2.bold())

            HStack(spacing: 12) {
                Button {
                    for c in conversations { store.toggleBase(c) }
                } label: {
                    Label(
                        allBases ? "Unmark All as Base" : "Mark All as Base",
                        systemImage: "star"
                    )
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete All…", systemImage: "trash")
                }
            }

            Button("Clear Selection", action: onClear)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete \(conversations.count) conversations?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Move to Trash", role: .destructive) {
                for c in conversations { store.delete(c) }
                onClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These will be moved to Trash.")
        }
    }

    private var allBases: Bool {
        !conversations.isEmpty && conversations.allSatisfy(\.isBase)
    }
}
