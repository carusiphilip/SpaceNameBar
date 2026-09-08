import Foundation
import Darwin

public struct StartupApp: Codable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let path: String
    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID; self.name = name; self.path = path
    }
}

public struct StartupSnapshot: Codable, Sendable {
    public var version = 1
    public let savedAt: Date
    public let apps: [StartupApp]
    public let spaces: [Space]
    public let labels: [String: String]

    public init(apps: [StartupApp], spaces: [Space], labels: [String: String], savedAt: Date = Date()) {
        self.savedAt = savedAt
        var seen = Set<String>()
        self.apps = apps.filter { !$0.bundleID.isEmpty && seen.insert($0.bundleID).inserted }
        self.spaces = spaces; self.labels = labels
    }
}

public struct StartupReceipt: Codable, Sendable {
    public var session: String
    public var attempts: [String: Int] = [:]
    public var failures: [String: String] = [:]
    public var completed = false
    public init(session: String, completed: Bool = false) { self.session = session; self.completed = completed }
}

public enum StartupError: LocalizedError {
    case invalidSnapshot, noSnapshot, unsafeLocation
    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot: "The saved startup app list could not be read. It has not been overwritten."
        case .noSnapshot: "Save your current apps before enabling startup restore."
        case .unsafeLocation: "The local startup data folder must be owned by your account and cannot be a symbolic link."
        }
    }
}

public final class StartupFiles {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> StartupSnapshot? {
        let current = directory.appendingPathComponent("startup.json")
        guard FileManager.default.fileExists(atPath: current.path) else { return nil }
        let result = try JSONDecoder().decode(StartupSnapshot.self, from: Data(contentsOf: current))
        guard result.version == 1, result.apps.count <= 256,
              Set(result.apps.map(\.bundleID)).count == result.apps.count else { throw StartupError.invalidSnapshot }
        return result
    }

    public func save(_ snapshot: StartupSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let current = directory.appendingPathComponent("startup.json")
        if let previous = try? Data(contentsOf: current) {
            // Keep the last known valid snapshot as an independent backup.
            if (try? JSONDecoder().decode(StartupSnapshot.self, from: previous)) != nil {
                try atomicWrite(previous, name: "startup.previous.json")
            }
        }
        try atomicWrite(data, name: "startup.json")
    }

    public func receipt() throws -> StartupReceipt? {
        let url = directory.appendingPathComponent("startup-receipt.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(StartupReceipt.self, from: Data(contentsOf: url))
    }

    public func saveReceipt(_ receipt: StartupReceipt) throws {
        try atomicWrite(JSONEncoder().encode(receipt), name: "startup-receipt.json")
    }

    private func atomicWrite(_ data: Data, name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw StartupError.unsafeLocation }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var template = Array(directory.appendingPathComponent(".write.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); unlink(temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(temporary, directory.appendingPathComponent(name).path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

@MainActor
public final class StartupEngine {
    private let files: StartupFiles
    public init(files: StartupFiles) { self.files = files }

    /// A receipt is written before each attempt, so a crash cannot create a launch loop.
    /// Running apps are never sent another open/reopen event.
    public func restore(_ snapshot: StartupSnapshot, session: String,
                        isRunning: (String) -> Bool,
                        launch: (StartupApp) async throws -> Void,
                        pause: () async throws -> Void) async throws -> StartupReceipt {
        var receipt = try files.receipt() ?? StartupReceipt(session: session)
        if receipt.session != session { receipt = StartupReceipt(session: session) }
        if receipt.completed { return receipt }
        for app in snapshot.apps {
            if isRunning(app.bundleID) { receipt.failures[app.bundleID] = nil; continue }
            while (receipt.attempts[app.bundleID] ?? 0) < 3 {
                try Task.checkCancellation()
                if isRunning(app.bundleID) { receipt.failures[app.bundleID] = nil; break }
                receipt.attempts[app.bundleID, default: 0] += 1
                try files.saveReceipt(receipt)
                do {
                    try await launch(app)
                    guard isRunning(app.bundleID) else { throw CocoaError(.executableNotLoadable) }
                    receipt.failures[app.bundleID] = nil
                    break
                } catch is CancellationError { throw CancellationError() }
                catch {
                    receipt.failures[app.bundleID] = error.localizedDescription
                    try files.saveReceipt(receipt)
                    if (receipt.attempts[app.bundleID] ?? 0) < 3 { try await pause() }
                }
            }
        }
        receipt.completed = true
        try files.saveReceipt(receipt)
        return receipt
    }
}
