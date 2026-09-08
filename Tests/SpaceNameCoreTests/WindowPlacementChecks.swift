import Foundation
import SpaceNameCore

func windowPlacementChecks() throws {
    func saved(_ id: String, _ title: String, _ document: String? = nil, terminalTitle: String? = nil) -> SavedWindow {
        SavedWindow(id: id, bundleID: "test.app", title: title, document: document, spaceID: "stable-space", fullScreen: false, terminalTitle: terminalTitle)
    }
    func live(_ id: UInt32, _ title: String, _ document: String? = nil) -> WindowCandidate {
        WindowCandidate(id: id, bundleID: "test.app", title: title, document: document)
    }
    let duplicate = [saved("a", "shell"), saved("b", "shell")]
    precondition(WindowMatcher.matches(saved: duplicate, live: [live(1, "shell"), live(2, "shell")]).isEmpty)
    let documents = [saved("a", "old", "file:///one"), saved("b", "old", "file:///two")]
    precondition(WindowMatcher.matches(saved: documents, live: [live(22, "changed", "file:///two"), live(33, "changed", "file:///one")]) == ["a":33, "b":22])
    precondition(WindowMatcher.matches(saved: [saved("a", "old")], live: [live(7, "new")]) == ["a":7])
    precondition(WindowMatcher.matches(saved: duplicate, live: [live(1, "shell")]).isEmpty)
    let slots = [saved("a", "", terminalTitle: "Build · Terminal 1"), saved("b", "", terminalTitle: "Build · Terminal 2")]
    precondition(WindowMatcher.matches(saved: slots, live: [live(44, "Build · Terminal 2"), live(55, "Build · Terminal 1")]) == ["a":55, "b":44])
    let snapshot = StartupSnapshot(apps: [], spaces: [], labels: [:], windows: slots)
    let decoded = try JSONDecoder().decode(StartupSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(decoded.windows == slots)
    var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
    old["version"] = 1; old.removeValue(forKey: "windows")
    let migrated = try JSONDecoder().decode(StartupSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
    precondition(migrated.windows == nil && migrated.version == 1)
    let oldReceipt = Data(#"{"session":"old","attempts":{},"failures":{},"completed":true}"#.utf8)
    let migratedReceipt = try JSONDecoder().decode(StartupReceipt.self, from: oldReceipt)
    precondition(migratedReceipt.placementCompleted == nil)
    print("PASS: ambiguous-window rejection, document identity, new window IDs, Terminal slots and snapshot/receipt migration.")
}
