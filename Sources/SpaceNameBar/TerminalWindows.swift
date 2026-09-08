import AppKit
import SpaceNameCore

@MainActor
enum TerminalWindows {
    static let bundleID = "com.apple.Terminal"

    /// A profile opens a fresh login shell. Never save or replay terminal commands.
    static func open(_ saved: SavedWindow, files: StartupFiles) async throws -> UInt32 {
        guard saved.bundleID == bundleID, !saved.fullScreen,
              let title = saved.terminalTitle, !title.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw WindowLayout.failure("This Terminal window cannot be recreated automatically.")
        }
        let before = Set(try WindowLayout.inventory(bundleIDs: [bundleID]).map { $0.candidate.id })
        let profile: [String: Any] = [
            "name": title, "type": "Window Settings", "ProfileCurrentVersion": 2.01,
            "WindowTitle": title, "ShowActiveProcessInTitle": false, "ShowShellCommandInTitle": false,
            "ShowWorkingDirectoryInTitle": false, "ShowWorkingDirectoryInTab": false,
            "ShowRepresentedURLInTitle": false, "ShowDimensionsInTitle": false,
            "columnCount": 100, "rowCount": 30
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        let url = try files.saveTerminalProfile(data, id: saved.id)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pending = PendingLaunch(continuation)
            pending.timeout = Task {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                pending.finish(WindowLayout.failure("Terminal took too long to open its saved window."))
            }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                Task { @MainActor in pending.finish(error) }
            }
        }
        for _ in 0..<75 {
            try await Task.sleep(for: .milliseconds(200))
            let fresh = try WindowLayout.inventory(bundleIDs: [bundleID], tolerateUnavailable: true).filter {
                !before.contains($0.candidate.id) && WindowMatcher.terminalTitleMatches($0.candidate.title, saved: title)
            }
            if fresh.count == 1 { return fresh[0].candidate.id }
        }
        throw WindowLayout.failure("Terminal opened without an identifiable saved window. No extra window was requested.")
    }
}
