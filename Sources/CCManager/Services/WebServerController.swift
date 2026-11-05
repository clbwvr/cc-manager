import Foundation
import AppKit

/// Runs the cc-web phone UI (a small Python server) for exactly as long as cc-manager
/// is open. Started on launch, terminated on quit — no standalone daemon. The server
/// also self-exits if this app dies unexpectedly (see watch_parent in server.py).
@MainActor
final class WebServerController {
    static let shared = WebServerController()

    private var process: Process?
    private let launcher = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("bin/cc-web.sh")

    func start() {
        guard process == nil, FileManager.default.fileExists(atPath: launcher.path) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [launcher.path]
        var env = ProcessInfo.processInfo.environment
        env["CC_WEB_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        p.environment = env
        do {
            try p.run()
            process = p
        } catch {
            NSLog("cc-web failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
