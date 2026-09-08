#if DEBUG
import AppKit
import SpaceNameCore

@MainActor
enum StartupIntegrationChecks {
    static func run(fixtureURL: URL) async throws {
        let id = "com.carusiphilip.SpaceNameBar.StartupProbe"
        guard Bundle(url: fixtureURL)?.bundleIdentifier == id else { throw CocoaError(.executableNotLoadable) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceNameBarLaunchCheck-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        }
        guard !StartupController.isRunning(id) else { throw CocoaError(.executableLoad) }
        let files = StartupFiles(directory: directory)
        let snapshot = StartupSnapshot(apps: [StartupApp(bundleID: id, name: "Startup Probe", path: fixtureURL.path)],
                                       spaces: [], labels: [:])
        try files.save(snapshot)
        let engine = StartupEngine(files: files)
        var launches = 0
        let launch: (StartupApp) async throws -> Void = { app in
            launches += 1
            try await StartupController.launch(app)
        }
        let first = try await engine.restore(try files.load()!, session: "fixture-boot1:login1",
            isRunning: StartupController.isRunning, launch: launch, pause: {})
        precondition(first.completed && first.failures.isEmpty && StartupController.isRunning(id))
        _ = try await engine.restore(try files.load()!, session: "fixture-boot1:login1",
            isRunning: StartupController.isRunning, launch: launch, pause: {})
        precondition(launches == 1, "App restart must not repeat startup launches")
        _ = try await engine.restore(try files.load()!, session: "fixture-boot2:login1",
            isRunning: StartupController.isRunning, launch: launch, pause: {})
        precondition(launches == 1, "Already-running apps must not receive another open event")
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        for _ in 0..<50 {
            if !StartupController.isRunning(id) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(!StartupController.isRunning(id), "Fixture must terminate before checking next-login restore")
        let next = try await engine.restore(try files.load()!, session: "fixture-boot3:login1",
            isRunning: StartupController.isRunning, launch: launch, pause: {})
        precondition(next.completed && next.failures.isEmpty && launches == 2 && StartupController.isRunning(id))
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        for _ in 0..<50 {
            if !StartupController.isRunning(id) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(!StartupController.isRunning(id))
        let suite = "SpaceNameBarStartupCheck.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "startup.restoreEnabled")
        let controller = StartupController(autoStart: false, defaults: preferences, files: files,
            initialDelay: .milliseconds(20), sessionProvider: { "fixture-boot4:login1" })
        controller.start() // Same eager entry point used by applicationDidFinishLaunching.
        var completed = false
        for _ in 0..<100 {
            let receipt = try files.receipt()
            if receipt?.session == "fixture-boot4:login1", receipt?.completed == true {
                completed = true; break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(completed && StartupController.isRunning(id))
        precondition(controller.status == "All 1 saved apps are running.")
        let duplicate = StartupController(autoStart: false, defaults: preferences, files: files,
            initialDelay: .milliseconds(20), sessionProvider: { "fixture-boot4:login1" })
        duplicate.start()
        try await Task.sleep(for: .milliseconds(100))
        let duplicateReceipt = try files.receipt()
        precondition(!duplicate.busy && duplicateReceipt?.attempts[id] == 1)
        _ = try StartupController.sessionIdentifier()
        print("PASS: actual app launch, disk reload, duplicate avoidance, new-login relaunch, automatic startup controller without opening a menu, and live session identification.")
    }
}
#endif
