import Foundation
import CoreGraphics
import SpaceNameCore

private let first = "11111111-1111-1111-1111-111111111111"
private let second = "22222222-2222-2222-2222-222222222222"
private let fullscreen = "33333333-3333-3333-3333-333333333333"

private func item(_ uuid: String, _ id: Int, type: Int = 0) -> [String: Any] {
    ["uuid": uuid, "id64": id, "ManagedSpaceID": id, "type": type]
}

private func display(_ id: String, current: [String: Any], spaces: [[String: Any]]) -> [String: Any] {
    ["Display Identifier": id, "Current Space": current, "Spaces": spaces]
}

func labelsFollowUUIDAcrossReorderingAndNewSessionIDs() {
    let original = SpaceParser.parse([display("screen", current: item(first, 4),
        spaces: [item(first, 4), item(second, 8)])])
    let rebooted = SpaceParser.parse([display("screen", current: item(first, 109),
        spaces: [item(second, 101), item(first, 109)])])
    check(original.first?.id == rebooted.last?.id)
    check(original.first?.number == 1)
    check(rebooted.last?.number == 2)
    check(SpaceParser.current(in: rebooted, displayID: "screen")?.id == first)
}

func fullscreenSharesTheDesktopNumberSequence() {
    let spaces = SpaceParser.parse([display("screen", current: item(fullscreen, 3, type: 4),
        spaces: [item(first, 1), item(fullscreen, 3, type: 4), item(second, 2)])])
    check(spaces.map(\.defaultName) == ["Desktop 1", "Desktop 2", "Desktop 3"])
    check(SpaceParser.current(in: spaces, displayID: "screen")?.isFullScreen == true)
}

func multipleDisplaysRequireAnUnambiguousTarget() {
    let spaces = SpaceParser.parse([
        display("left", current: item(first, 1), spaces: [item(first, 1)]),
        display("right", current: item(second, 2), spaces: [item(second, 2)])])
    check(SpaceParser.current(in: spaces, displayID: "right")?.id == second)
    check(SpaceParser.current(in: spaces, displayID: "missing") == nil)
    check(SpaceParser.current(in: spaces, displayID: nil) == nil)
}

func unifiedDisplaysCanUseTheSingleVisibleSpace() {
    let spaces = SpaceParser.parse([display("Main", current: item(first, 1), spaces: [item(first, 1)])])
    check(SpaceParser.current(in: spaces, displayID: "physical-display-uuid")?.id == first)
}

func malformedAndUnstableIdentifiersAreNeverPersistable() {
    let spaces = SpaceParser.parse([[:], display("screen", current: item(first, 1), spaces: [
        ["id64": 2, "type": 0], item("", 3), item("garbage", 4),
        item(second, 5, type: 6), item(first, 1)])])
    check(spaces.count == 1)
    check(spaces.first?.id == first)
}

func currentSpaceCanBeResolvedWhenItsUUIDIsOmitted() {
    let spaces = SpaceParser.parse([display("screen", current: ["ManagedSpaceID": 7], spaces: [item(first, 7)])])
    check(spaces.first?.isCurrent == true)
    let unknown = SpaceParser.parse([display("screen", current: [:], spaces: [item(first, 7)])])
    check(unknown.first?.isCurrent == false)
}

func persistenceResetAndIndependentSpaces() throws {
    let suite = "SpaceNameBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = LabelStore(defaults: defaults)
    store.set("  💬 Agent Runners  ", for: first)
    store.set("Documentation", for: second)
    let reopened = LabelStore(defaults: UserDefaults(suiteName: suite)!)
    check(reopened.label(for: first) == "💬 Agent Runners")
    check(reopened.label(for: second) == "Documentation")
    reopened.set(" \n ", for: first)
    check(store.label(for: first) == nil)
    check(store.label(for: second) == "Documentation")
}

func labelLimitsPreserveEmojiAndRemoveNewlines() {
    check(LabelStore.cleaned("  One\nTwo  ") == "One Two")
    let long = String(repeating: "👨‍👩‍👧‍👦", count: 100)
    check(LabelStore.cleaned(long).count == 80)
    check(LabelStore.cleaned(long) == String(repeating: "👨‍👩‍👧‍👦", count: 80))
}

private func check(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    guard condition() else { fatalError("Check failed", file: file, line: line) }
}

func overlayCoordinatesWorkAcrossDisplays() {
    let primary = OverlayLayout.appKitFrame(CGRect(x: 20, y: 100, width: 200, height: 150), primaryTop: 1080)
    check(primary == CGRect(x: 20, y: 830, width: 200, height: 150))
    let above = OverlayLayout.appKitFrame(CGRect(x: -1400, y: -900, width: 100, height: 80), primaryTop: 1080)
    check(above == CGRect(x: -1400, y: 1900, width: 100, height: 80))
    let screen = CGRect(x: -1440, y: 1080, width: 1440, height: 900)
    let badge = OverlayLayout.badgeFrame(in: above, screen: screen)
    check(badge != nil && screen.contains(badge!))
    check(OverlayLayout.badgeFrame(in: .zero, screen: screen) == nil)
    check(OverlayLayout.badgeFrame(in: CGRect(x: 0, y: 0, width: 100, height: 100), screen: screen) == nil)
}

@main
struct CoreChecks {
    @MainActor static func main() async throws {
        labelsFollowUUIDAcrossReorderingAndNewSessionIDs()
        fullscreenSharesTheDesktopNumberSequence()
        multipleDisplaysRequireAnUnambiguousTarget()
        unifiedDisplaysCanUseTheSingleVisibleSpace()
        malformedAndUnstableIdentifiersAreNeverPersistable()
        currentSpaceCanBeResolvedWhenItsUUIDIsOmitted()
        try persistenceResetAndIndependentSpaces()
        labelLimitsPreserveEmojiAndRemoveNewlines()
        overlayCoordinatesWorkAcrossDisplays()
        print("Passed all 9 SpaceNameCore checks.")
        try await startupChecks()
    }
}
