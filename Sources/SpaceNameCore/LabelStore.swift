import Foundation

public final class LabelStore {
    public static let storageKey = "spaceLabels.v1"
    public static let maximumLength = 80
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func label(for id: String) -> String? {
        (defaults.dictionary(forKey: Self.storageKey) as? [String: String])?[id]
    }

    public func set(_ text: String, for id: String) {
        var labels = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        let clean = Self.cleaned(text)
        labels[id] = clean.isEmpty ? nil : clean
        defaults.set(labels, forKey: Self.storageKey)
    }

    public static func cleaned(_ text: String) -> String {
        let singleLine = text.components(separatedBy: .newlines).joined(separator: " ")
        return String(singleLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }
}
