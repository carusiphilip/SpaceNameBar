import Foundation

public struct SavedWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let bundleID: String
    public let title: String
    public let document: String?
    public let spaceID: String
    public let fullScreen: Bool
    public let terminalTitle: String?
    public init(id: String = UUID().uuidString, bundleID: String, title: String, document: String?, spaceID: String, fullScreen: Bool,
                terminalTitle: String? = nil) {
        self.id = id; self.bundleID = bundleID; self.title = title
        self.document = document; self.spaceID = spaceID; self.fullScreen = fullScreen
        self.terminalTitle = terminalTitle
    }
}

public struct WindowCandidate: Equatable, Sendable {
    public let id: UInt32
    public let bundleID: String
    public let title: String
    public let document: String?
    public init(id: UInt32, bundleID: String, title: String, document: String?) {
        self.id = id; self.bundleID = bundleID; self.title = title; self.document = document
    }
}

public enum WindowMatcher {
    public static func terminalTitleMatches(_ live: String, saved: String) -> Bool {
        live == saved || live.hasPrefix(saved + " — ")
    }
    /// Only accept unique, mutually unambiguous identities. Never use an old
    /// numeric window ID across login sessions or guess between identical titles.
    public static func matches(saved: [SavedWindow], live: [WindowCandidate]) -> [String: UInt32] {
        var result: [String: UInt32] = [:]
        var used = Set<UInt32>()
        for item in saved {
            guard let title = item.terminalTitle else { continue }
            let candidates = live.filter { $0.bundleID == item.bundleID && terminalTitleMatches($0.title, saved: title) }
            if candidates.count == 1, !used.contains(candidates[0].id),
               saved.filter({ $0.terminalTitle == title }).count == 1 {
                result[item.id] = candidates[0].id; used.insert(candidates[0].id)
            }
        }
        for matchDocument in [true, false] {
            for item in saved where result[item.id] == nil {
                let key = matchDocument ? item.document ?? "" : item.title
                guard !key.isEmpty else { continue }
                let sameSaved = saved.filter {
                    result[$0.id] == nil && $0.bundleID == item.bundleID &&
                    (matchDocument ? $0.document ?? "" : $0.title) == key
                }
                let candidates = live.filter {
                    !used.contains($0.id) && $0.bundleID == item.bundleID &&
                    (matchDocument ? $0.document ?? "" : $0.title) == key
                }
                if sameSaved.count == 1, candidates.count == 1 {
                    result[item.id] = candidates[0].id
                    used.insert(candidates[0].id)
                }
            }
        }
        // A sole window for an app can change title while opening its document.
        for item in saved where result[item.id] == nil {
            let appSaved = saved.filter { $0.bundleID == item.bundleID }
            let appLive = live.filter { $0.bundleID == item.bundleID }
            if appSaved.count == 1, appLive.count == 1, !used.contains(appLive[0].id) {
                result[item.id] = appLive[0].id
                used.insert(appLive[0].id)
            }
        }
        return result
    }
}
