import SwiftUI

@main
struct CCManagerApp: App {
    @StateObject private var store = ConversationStore()

    var body: some Scene {
        WindowGroup("Claude Conversations") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 600)
                .task { await store.load() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reload") {
                    Task { await store.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
