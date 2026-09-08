import AppKit
import SpaceNameCore
import WindowSpaceBridge

@MainActor
enum WindowLayout {
    struct LiveWindow {
        let candidate: WindowCandidate
        let spaces: Set<UInt64>
        let fullScreen: Bool
    }

    static func membership(_ id: UInt32) -> Set<UInt64> {
        guard let values = SNBCopyWindowSpaces(id) as? [NSNumber] else { return [] }
        return Set(values.map(\.uint64Value))
    }

    static func inventory(bundleIDs: Set<String>, tolerateUnavailable: Bool = false) throws -> [LiveWindow] {
        guard AXIsProcessTrusted() else { throw failure("Enable Accessibility for SpaceNameBar to save and restore window placement.") }
        var result: [LiveWindow] = []
        var excludedIDs = Set<UInt32>()
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, bundleIDs.contains(bundleID), !app.isTerminated else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 1)
            var raw: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw)
            if CommandLine.arguments.contains("--window-access-status") {
                print("\(bundleID): AXWindows status \(error.rawValue), count \((raw as? [AXUIElement])?.count ?? 0)")
            }
            if error == .noValue || error == .attributeUnsupported { continue }
            guard error == .success, let windows = raw as? [AXUIElement] else {
                if tolerateUnavailable { continue }
                throw failure("Could not read windows from \(app.localizedName ?? bundleID). Try again when the app responds.")
            }
            for window in windows {
                func attribute(_ key: String) -> CFTypeRef? {
                    var value: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(window, key as CFString, &value) == .success else { return nil }
                    return value
                }
                let fullScreen = (attribute("AXFullScreen") as? NSNumber)?.boolValue ?? false
                let subrole = attribute(kAXSubroleAttribute) as? String
                if CommandLine.arguments.contains("--window-access-status") {
                    print("\(bundleID): subrole=\(subrole ?? "none") fullscreen=\(fullScreen) id=\(SNBWindowID(window) != 0)")
                }
                guard subrole == kAXStandardWindowSubrole || fullScreen else {
                    excludedIDs.insert(SNBWindowID(window)); continue
                }
                let id = SNBWindowID(window)
                guard id != 0 else { continue }
                result.append(LiveWindow(candidate: WindowCandidate(id: id, bundleID: bundleID,
                    title: attribute(kAXTitleAttribute) as? String ?? "",
                    document: attribute(kAXDocumentAttribute) as? String),
                    spaces: membership(id), fullScreen: fullScreen))
            }
        }
        // macOS can omit windows on inactive Spaces from AXWindows.
        // WindowServer still exposes their IDs
        // and ownership without requesting screen pixels or Screen Recording.
        let known = Set(result.map { $0.candidate.id })
        let managed = try SpaceDetector().managedSpaceIDs()
        let fullScreenIDs = Set(try SpaceDetector().allSpaces().filter(\.isFullScreen).compactMap { managed[$0.id] })
        if let raw = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in raw {
                guard let number = info[kCGWindowNumber as String] as? NSNumber, !known.contains(number.uint32Value),
                      !excludedIDs.contains(number.uint32Value),
                      (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                      let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
                      let app = NSRunningApplication(processIdentifier: pid.int32Value),
                      let bundleID = app.bundleIdentifier, bundleIDs.contains(bundleID) else { continue }
                let spaces = membership(number.uint32Value)
                guard spaces.count == 1, !spaces.isDisjoint(with: Set(managed.values)),
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds), frame.width >= 80, frame.height >= 50 else { continue }
                result.append(LiveWindow(candidate: WindowCandidate(id: number.uint32Value, bundleID: bundleID,
                    title: info[kCGWindowName as String] as? String ?? "", document: nil),
                    spaces: spaces, fullScreen: !spaces.isDisjoint(with: fullScreenIDs)))
            }
        }
        return result
    }

    static func capture(apps: [StartupApp], spaces: [Space], labels: [String: String], previous: [SavedWindow] = []) throws -> [SavedWindow] {
        let ids = try SpaceDetector().managedSpaceIDs()
        var terminalCounts: [String: Int] = [:]
        var reusedIDs = Set<String>()
        return try inventory(bundleIDs: Set(apps.map(\.bundleID))).compactMap { live in
            let targets = spaces.filter { ids[$0.id].map(live.spaces.contains) ?? false }
            // Windows pinned to all desktops have no single destination.
            guard targets.count == 1 else { return nil }
            let target = targets[0]
            if live.candidate.bundleID == TerminalWindows.bundleID, !target.isFullScreen {
                terminalCounts[target.id, default: 0] += 1
                if let existing = previous.first(where: {
                    $0.spaceID == target.id && $0.terminalTitle.map { WindowMatcher.terminalTitleMatches(live.candidate.title, saved: $0) } == true
                }), reusedIDs.insert(existing.id).inserted { return existing }
                return SavedWindow(bundleID: live.candidate.bundleID, title: live.candidate.title, document: live.candidate.document,
                    spaceID: target.id, fullScreen: false,
                    terminalTitle: "\(labels[target.id] ?? target.defaultName) · Terminal \(terminalCounts[target.id]!)")
            }
            return SavedWindow(bundleID: live.candidate.bundleID, title: live.candidate.title,
                document: live.candidate.document, spaceID: targets[0].id,
                fullScreen: targets[0].isFullScreen || live.fullScreen)
        }
    }

    static func move(_ windowID: UInt32, to spaceID: UInt64) async throws {
        if membership(windowID) == [spaceID] { return }
        guard SNBCanMoveWindows(), SNBMoveWindow(windowID, spaceID) else {
            throw failure("Window placement is unavailable on this macOS version.")
        }
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if membership(windowID) == [spaceID] { return }
        }
        throw failure("macOS did not move a window to its saved desktop.")
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "SpaceNameBar.Layout", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
