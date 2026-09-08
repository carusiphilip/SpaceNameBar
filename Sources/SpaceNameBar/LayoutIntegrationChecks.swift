import AppKit
import SpaceNameCore

@MainActor
enum LayoutIntegrationChecks {
    static func run() async throws {
        let detector = SpaceDetector()
        let spaces = try detector.allSpaces().filter { !$0.isFullScreen }
        let ids = try detector.managedSpaceIDs()
        guard spaces.count >= 2, let bundleID = Bundle.main.bundleIdentifier, let appURL = Bundle.main.bundleURL as URL? else {
            throw WindowLayout.failure("Run the installed app with two ordinary desktops available.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceNameBarLayoutCheck-\(UUID().uuidString)")
        let suite = "SpaceNameBarLayoutCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let files = StartupFiles(directory: directory)
        var windows: [NSWindow] = []
        defer {
            windows.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        for index in 1...2 {
            let window = NSWindow(contentRect: NSRect(x: 50 + index * 20, y: 50, width: 240, height: 100),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "SpaceNameBar test window \(index)"
            window.orderFront(nil)
            windows.append(window)
        }
        try await Task.sleep(for: .milliseconds(500))
        let saved = zip(windows, spaces.prefix(2)).map { window, space in
            SavedWindow(bundleID: bundleID, title: window.title, document: nil, spaceID: space.id, fullScreen: false)
        }
        let snapshot = StartupSnapshot(apps: [StartupApp(bundleID: bundleID, name: "Layout Probe", path: appURL.path)],
            spaces: spaces, labels: [:], windows: saved)
        try files.save(snapshot)
        // Simulate a crash after app launches completed but before placement began.
        try files.saveReceipt(StartupReceipt(session: "fixture-new-login", completed: true))
        defaults.set(true, forKey: "startup.restoreEnabled")
        let controller = StartupController(autoStart: false, defaults: defaults, files: files,
            initialDelay: .milliseconds(20), sessionProvider: { "fixture-new-login" })
        controller.start()
        var completed = false
        for _ in 0..<100 {
            if try files.receipt()?.placementCompleted == true { completed = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let receipt = try files.receipt()
        guard completed, receipt?.placementFailures?.isEmpty == true else {
            throw WindowLayout.failure("Automatic placement test failed: \(controller.status)")
        }
        for (window, target) in zip(windows, spaces.prefix(2)) {
            guard WindowLayout.membership(UInt32(window.windowNumber)) == [ids[target.id]!] else {
                throw WindowLayout.failure("A test window did not reach its saved desktop.")
            }
        }
        let firstID = UInt32(windows[0].windowNumber)
        let other = ids[spaces[1].id]!
        try await WindowLayout.move(firstID, to: other)
        let duplicate = StartupController(autoStart: false, defaults: defaults, files: files,
            initialDelay: .milliseconds(20), sessionProvider: { "fixture-new-login" })
        duplicate.start()
        try await Task.sleep(for: .milliseconds(300))
        guard !duplicate.busy, WindowLayout.membership(firstID) == [other] else {
            throw WindowLayout.failure("Same-login relaunch repeated placement unexpectedly.")
        }
        print("PASS: automatic placement of two real windows on distinct desktops, recovery after launch-stage completion, verified memberships, and no same-login repeat.")
    }
}
