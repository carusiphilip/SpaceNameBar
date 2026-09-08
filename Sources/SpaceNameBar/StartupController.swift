import AppKit
import Combine
import Security
import ServiceManagement
import SpaceNameCore

@MainActor
final class StartupController: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var snapshot: StartupSnapshot?
    @Published private(set) var status = "No apps saved yet."
    @Published private(set) var busy = false
    private let files: StartupFiles
    private let defaults: UserDefaults
    private let initialDelay: Duration
    private let sessionProvider: () throws -> String
    private var restoreTask: Task<Void, Never>?

    init(autoStart: Bool = true, defaults: UserDefaults = .standard, files: StartupFiles? = nil,
         initialDelay: Duration = .seconds(15),
         sessionProvider: @escaping () throws -> String = { try StartupController.sessionIdentifier() }) {
        self.defaults = defaults
        self.initialDelay = initialDelay
        self.sessionProvider = sessionProvider
        enabled = defaults.bool(forKey: "startup.restoreEnabled")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpaceNameBar", isDirectory: true)
        self.files = files ?? StartupFiles(directory: directory)
        do {
            snapshot = try self.files.load()
            if let snapshot {
                status = "\(snapshot.apps.count) apps saved for startup."
                // Recover only an entirely missing label store, never resurrect intentionally reset names.
                if defaults.object(forKey: LabelStore.storageKey) == nil {
                    defaults.set(snapshot.labels, forKey: LabelStore.storageKey)
                }
            }
        } catch { status = error.localizedDescription }
        if autoStart, !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
            scheduleRestore()
        }
    }

    func captureAndEnable() throws {
        guard !busy else { return }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> StartupApp? in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  let url = app.bundleURL else { return nil }
            return StartupApp(bundleID: id, name: app.localizedName ?? id, path: url.path)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !apps.isEmpty else { throw StartupError.noSnapshot }
        let labels = defaults.dictionary(forKey: LabelStore.storageKey) as? [String: String] ?? [:]
        let captured = StartupSnapshot(apps: apps, spaces: try SpaceDetector().allSpaces(), labels: labels)
        try files.save(captured)
        // Saving now must not reopen apps during this same login session.
        try files.saveReceipt(StartupReceipt(session: try sessionProvider(), completed: true))
        snapshot = try files.load()
        try enable(true)
        status = "Saved \(apps.count) apps and \(labels.count) custom names."
    }

    func saveCurrentApps() {
        do { try captureAndEnable() } catch { status = error.localizedDescription }
    }

    func setEnabled(_ value: Bool) {
        do { try enable(value) } catch { status = error.localizedDescription }
    }

    private func enable(_ value: Bool) throws {
        if value {
            guard snapshot != nil else { throw StartupError.noSnapshot }
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            guard SMAppService.mainApp.status == .enabled else {
                throw NSError(domain: "SpaceNameBar", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Allow SpaceNameBar in System Settings → General → Login Items & Extensions."])
            }
        } else { restoreTask?.cancel(); busy = false }
        enabled = value
        defaults.set(value, forKey: "startup.restoreEnabled")
    }

    private func scheduleRestore() {
        guard enabled, let snapshot else { return }
        do {
            let session = try sessionProvider()
            if let receipt = try files.receipt(), receipt.session == session, receipt.completed {
                if !receipt.failures.isEmpty { status = "\(receipt.failures.count) apps could not be reopened. Use Reopen saved apps to retry." }
                return
            }
            let delay = initialDelay
            restoreTask = Task { [weak self] in
                do {
                    // Give macOS session restoration time to start apps first.
                    try await Task.sleep(for: delay)
                    guard let self, self.enabled else { return }
                    await self.runRestore(snapshot, session: session)
                } catch { }
            }
        } catch { status = error.localizedDescription }
    }

    func start() { scheduleRestore() }

    func restoreNow() {
        guard let snapshot, !busy else { return }
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try self.sessionProvider()
                try self.files.saveReceipt(StartupReceipt(session: session))
                await self.runRestore(snapshot, session: session)
            } catch { self.status = error.localizedDescription }
        }
    }

    private func runRestore(_ snapshot: StartupSnapshot, session: String) async {
        busy = true
        status = "Reopening saved apps…"
        defer { busy = false }
        do {
            let receipt = try await StartupEngine(files: files).restore(snapshot, session: session,
                isRunning: Self.isRunning, launch: Self.launch,
                pause: { try await Task.sleep(for: .seconds(3)) })
            if receipt.failures.isEmpty { status = "All \(snapshot.apps.count) saved apps are running." }
            else {
                let names = snapshot.apps.filter { receipt.failures[$0.bundleID] != nil }.map(\.name)
                status = "Could not reopen: \(names.joined(separator: ", "))."
            }
        } catch { status = error.localizedDescription }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    static func launch(_ app: StartupApp) async throws {
        if isRunning(app.bundleID) { return }
        let recorded = URL(fileURLWithPath: app.path)
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        guard let url = [registered, recorded].compactMap({ $0 }).first(where: {
            $0.isFileURL && $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == app.bundleID
        }) else {
            throw NSError(domain: "SpaceNameBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(app.name) is no longer installed."])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pending = PendingLaunch(continuation)
            pending.timeout = Task {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                pending.finish(NSError(domain: "SpaceNameBar", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "\(app.name) took too long to launch."]))
            }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                let succeeded = application != nil
                Task { @MainActor in
                    pending.finish(error ?? (succeeded ? nil : CocoaError(.executableNotLoadable)))
                }
            }
        }
    }

    static func sessionIdentifier() throws -> String {
        var session: SecuritySessionId = 0
        guard SessionGetInfo(callerSecuritySession, &session, nil) == errSecSuccess else {
            throw NSError(domain: "SpaceNameBar", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not identify the login session."])
        }
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return "\(boot.tv_sec).\(boot.tv_usec):\(session)"
    }
}

@MainActor
private final class PendingLaunch {
    private var continuation: CheckedContinuation<Void, Error>?
    var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
