import Foundation
import SpaceNameCore

@MainActor
func startupChecks() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceNameBarChecks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = StartupFiles(directory: directory)
    let alpha = StartupApp(bundleID: "test.alpha", name: "Alpha", path: "/Applications/Alpha.app")
    let beta = StartupApp(bundleID: "test.beta", name: "Beta", path: "/Applications/Beta.app")
    let gamma = StartupApp(bundleID: "test.gamma", name: "Gamma", path: "/Applications/Gamma.app")
    let snapshot = StartupSnapshot(apps: [alpha, beta, gamma, alpha], spaces: [], labels: ["fixture": "💬 Example"])
    try files.save(snapshot)
    let reopened = StartupFiles(directory: directory)
    let loaded = try reopened.load()!
    precondition(loaded.apps == [alpha, beta, gamma], "Snapshot round-trip and deduplication")
    precondition(loaded.labels["fixture"] == "💬 Example", "Labels must be backed up exactly")
    let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("startup.json").path)[.posixPermissions] as? NSNumber
    precondition(mode?.intValue == 0o600, "Snapshot must be owner-only")
    var running: Set<String> = [alpha.bundleID]
    var calls: [String: Int] = [:]
    let engine = StartupEngine(files: files)
    let result = try await engine.restore(loaded, session: "boot1:login1", isRunning: { running.contains($0) }, launch: { app in
        calls[app.bundleID, default: 0] += 1
        if app.bundleID == beta.bundleID, calls[app.bundleID] == 1 { throw CocoaError(.executableNotLoadable) }
        if app.bundleID == gamma.bundleID { throw CocoaError(.fileNoSuchFile) }
        running.insert(app.bundleID)
    }, pause: {})
    precondition(calls[alpha.bundleID] == nil, "Running apps must never be reopened")
    precondition(calls[beta.bundleID] == 2, "Transient failure must retry")
    precondition(calls[gamma.bundleID] == 3, "Permanent failure must stop at three attempts")
    precondition(result.completed && result.failures.count == 1 && result.failures[gamma.bundleID] != nil)
    let before = calls
    _ = try await engine.restore(loaded, session: "boot1:login1", isRunning: { _ in false }, launch: { app in
        calls[app.bundleID, default: 0] += 1
    }, pause: {})
    precondition(calls == before, "Same login session must not run twice")
    running = []
    calls = [:]
    let next = try await engine.restore(loaded, session: "boot2:login1", isRunning: { running.contains($0) }, launch: { app in
        calls[app.bundleID, default: 0] += 1; running.insert(app.bundleID)
    }, pause: {})
    precondition(next.failures.isEmpty && calls.values.reduce(0, +) == 3, "A new boot must restore all missing apps")
    var interrupted = StartupReceipt(session: "boot3:login1")
    interrupted.attempts[gamma.bundleID] = 3
    interrupted.failures[gamma.bundleID] = "Previous attempts failed"
    try files.saveReceipt(interrupted)
    running = [alpha.bundleID, beta.bundleID]
    calls = [:]
    _ = try await engine.restore(loaded, session: interrupted.session, isRunning: { running.contains($0) }, launch: { app in
        calls[app.bundleID, default: 0] += 1
    }, pause: {})
    precondition(calls.isEmpty, "A crash must not reset the attempt limit")
    try files.save(StartupSnapshot(apps: [beta], spaces: [], labels: [:]))
    let backup = try JSONDecoder().decode(StartupSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("startup.previous.json")))
    precondition(backup.labels == loaded.labels, "Saving a new snapshot must keep the previous snapshot")
    try Data("corrupt".utf8).write(to: directory.appendingPathComponent("startup.json"))
    do { _ = try files.load(); preconditionFailure("Corruption must not silently erase saved apps") } catch { }
    print("Passed startup checks: persistence, file privacy, deduplication, retries, failure reporting, reboot/login gating, crash recovery, backups and corruption handling.")
}
