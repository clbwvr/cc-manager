import SwiftUI

@main
struct CCManagerApp: App {
    @StateObject private var store = ConversationStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

/// Owns the cc-web phone server's lifecycle: up while the app runs, down on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WebServerController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WebServerController.shared.stop()
    }
}
