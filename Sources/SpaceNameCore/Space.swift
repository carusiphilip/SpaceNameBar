import Foundation

public struct Space: Equatable, Identifiable, Sendable, Codable {
    public let id: String
    public let displayID: String
    public let number: Int
    public let isFullScreen: Bool
    public let isCurrent: Bool

    public var defaultName: String {
        "Desktop \(number)"
    }

    public init(id: String, displayID: String, number: Int, isFullScreen: Bool, isCurrent: Bool) {
        self.id = id
        self.displayID = displayID
        self.number = number
        self.isFullScreen = isFullScreen
        self.isCurrent = isCurrent
    }
}

public enum SpaceParser {
    /// Only UUIDs are safe persistence keys. Numeric WindowServer IDs are session-scoped.
    public static func parse(_ displays: [[String: Any]]) -> [Space] {
        var result: [Space] = []
        var desktopNumber = 0
        for display in displays {
            guard let displayID = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let current = display["Current Space"] as? [String: Any]
            let currentUUID = canonicalUUID(current?["uuid"])
            let currentID = (current?["ManagedSpaceID"] as? NSNumber)?.uint64Value
                ?? (current?["id64"] as? NSNumber)?.uint64Value
            for info in spaces {
                guard let uuid = canonicalUUID(info["uuid"]),
                      let type = info["type"] as? NSNumber,
                      type.intValue == 0 || type.intValue == 4 else { continue }
                let isFullScreen = type.intValue == 4
                desktopNumber += 1
                let numericID = (info["ManagedSpaceID"] as? NSNumber)?.uint64Value
                    ?? (info["id64"] as? NSNumber)?.uint64Value
                let matches = currentUUID.map { $0 == uuid }
                    ?? (currentID != nil && numericID == currentID)
                result.append(Space(id: uuid, displayID: displayID,
                                    number: desktopNumber,
                                    isFullScreen: isFullScreen, isCurrent: matches))
            }
        }
        return result
    }

    public static func current(in spaces: [Space], displayID: String?) -> Space? {
        let visible = spaces.filter(\.isCurrent)
        if let displayID, let match = visible.first(where: { $0.displayID == displayID }) {
            return match
        }
        // Unified Spaces often reports "Main" instead of a physical display UUID.
        return visible.count == 1 ? visible.first : nil
    }

    private static func canonicalUUID(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return UUID(uuidString: value)?.uuidString
    }
}
