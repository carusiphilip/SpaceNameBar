import AppKit
import SpaceNameCore

@MainActor
enum LayoutRestorer {
    static func restore(_ snapshot: StartupSnapshot, receipt initial: StartupReceipt, files: StartupFiles,
                        settlePasses: Int = 30, pause: () async throws -> Void = {
                            try await Task.sleep(for: .seconds(1))
                        }) async throws -> StartupReceipt {
        guard let saved = snapshot.windows, !saved.isEmpty else { return initial }
        var receipt = initial
        var placed = Set<String>()
        var failures: [String: String] = [:]
        let bundleIDs = Set(saved.map(\.bundleID))
        // Give each app's native session restoration time to produce its windows.
        for pass in 0..<max(1, settlePasses) {
            try Task.checkCancellation()
            let live = try WindowLayout.inventory(bundleIDs: bundleIDs, tolerateUnavailable: true)
            let ids = try SpaceDetector().managedSpaceIDs()
            let matches = assignments(saved: saved, live: live, spaceIDs: ids)
            for item in saved where !placed.contains(item.id) {
                guard let target = ids[item.spaceID] else {
                    failures[item.id] = "The saved desktop no longer exists."; continue
                }
                guard let windowID = matches[item.id], let window = live.first(where: { $0.candidate.id == windowID }) else {
                    failures[item.id] = "The app has not reopened an identifiable matching window."; continue
                }
                if window.spaces == [target] { placed.insert(item.id); failures[item.id] = nil; continue }
                guard !item.fullScreen, !window.fullScreen else {
                    failures[item.id] = "A full-screen arrangement must be restored by macOS or its app."; continue
                }
                do {
                    try await WindowLayout.move(windowID, to: target)
                    placed.insert(item.id); failures[item.id] = nil
                } catch is CancellationError { throw CancellationError() }
                catch { failures[item.id] = error.localizedDescription }
            }
            if placed.count == saved.count { break }
            if pass + 1 < settlePasses { try await pause() }
        }
        // Recreate missing Terminal shells only after the native restore grace period.
        // A checkpoint BEFORE every open prevents an app crash from creating duplicates.
        let live = try WindowLayout.inventory(bundleIDs: bundleIDs, tolerateUnavailable: true)
        let ids = try SpaceDetector().managedSpaceIDs()
        var deficit = max(0, saved.filter { $0.bundleID == TerminalWindows.bundleID }.count -
                          live.filter { $0.candidate.bundleID == TerminalWindows.bundleID }.count)
        for item in saved where !placed.contains(item.id) && item.bundleID == TerminalWindows.bundleID {
            guard !item.fullScreen, let target = ids[item.spaceID], item.terminalTitle != nil else { continue }
            guard deficit > 0 else {
                failures[item.id] = "Terminal windows exist but cannot be identified safely. No duplicates were opened."; continue
            }
            guard !(receipt.terminalAttempts ?? []).contains(item.id) else {
                failures[item.id] = "A Terminal open was already attempted this login. Use Restore saved layout to retry."; continue
            }
            receipt.terminalAttempts = (receipt.terminalAttempts ?? []) + [item.id]
            try files.saveReceipt(receipt)
            do {
                let windowID = try await TerminalWindows.open(item, files: files)
                deficit -= 1
                try await WindowLayout.move(windowID, to: target)
                placed.insert(item.id); failures[item.id] = nil
            } catch is CancellationError { throw CancellationError() }
            catch { failures[item.id] = error.localizedDescription; break }
        }
        receipt.placementCompleted = true
        receipt.placementFailures = failures
        try files.saveReceipt(receipt)
        return receipt
    }

    static func assignments(saved: [SavedWindow], live: [WindowLayout.LiveWindow], spaceIDs: [String: UInt64]) -> [String: UInt32] {
        var matches = WindowMatcher.matches(saved: saved, live: live.map(\.candidate))
        var used = Set(matches.values)
        // For a requested fresh Terminal slot, a Terminal already on that desktop
        // satisfies the count. Do not move anonymous windows away from another task.
        for item in saved where matches[item.id] == nil && item.bundleID == TerminalWindows.bundleID && item.title.isEmpty {
            guard let target = spaceIDs[item.spaceID], let window = live.first(where: {
                $0.candidate.bundleID == item.bundleID && $0.spaces == [target] && !used.contains($0.candidate.id) && !$0.fullScreen
            }) else { continue }
            matches[item.id] = window.candidate.id; used.insert(window.candidate.id)
        }
        // Anonymous windows satisfy a saved slot only when already on
        // their original stable desktop. Never infer a new desktop from its number.
        for item in saved where matches[item.id] == nil && item.title.isEmpty {
            guard let target = spaceIDs[item.spaceID] else { continue }
            let candidates = live.filter {
                $0.candidate.bundleID == item.bundleID && $0.spaces == [target] && !used.contains($0.candidate.id)
            }
            if let candidate = candidates.first {
                matches[item.id] = candidate.candidate.id; used.insert(candidate.candidate.id)
            }
        }
        // Identical titles on different desktops are ambiguous for moving, but
        // their existing positions can still satisfy the saved per-desktop count.
        for item in saved where matches[item.id] == nil && !item.title.isEmpty {
            guard let target = spaceIDs[item.spaceID], let window = live.first(where: {
                $0.candidate.bundleID == item.bundleID && $0.candidate.title == item.title &&
                $0.spaces == [target] && !used.contains($0.candidate.id)
            }) else { continue }
            matches[item.id] = window.candidate.id; used.insert(window.candidate.id)
        }
        // Titles may change while an app loads, or be unavailable on an inactive
        // desktop. A window already on the correct desktop satisfies its app's
        // slot; this fallback never moves a window between tasks.
        for item in saved where matches[item.id] == nil {
            guard let target = spaceIDs[item.spaceID], let window = live.first(where: {
                $0.candidate.bundleID == item.bundleID && $0.spaces == [target] && !used.contains($0.candidate.id)
            }) else { continue }
            matches[item.id] = window.candidate.id; used.insert(window.candidate.id)
        }
        return matches
    }

    static func verify(_ snapshot: StartupSnapshot) throws -> (placed: Int, total: Int) {
        let saved = snapshot.windows ?? []
        let live = try WindowLayout.inventory(bundleIDs: Set(saved.map(\.bundleID)))
        let ids = try SpaceDetector().managedSpaceIDs()
        let matches = assignments(saved: saved, live: live, spaceIDs: ids)
        let placed = saved.filter { item in
            guard let id = matches[item.id], let target = ids[item.spaceID],
                  let window = live.first(where: { $0.candidate.id == id }) else { return false }
            return window.spaces == [target]
        }.count
        return (placed, saved.count)
    }
}
