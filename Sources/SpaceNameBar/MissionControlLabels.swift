import AppKit
import ApplicationServices
import Combine
import SpaceNameCore

/// Observes the Dock through Accessibility. No key interception, injection, or Dock mutations.
@MainActor
final class MissionControlLabels: ObservableObject {
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var status = ""
    @Published var desktopLabels: Bool {
        didSet { UserDefaults.standard.set(desktopLabels, forKey: "missionControl.desktopLabels"); updateSettings() }
    }
    @Published var windowLabels: Bool {
        didSet { UserDefaults.standard.set(windowLabels, forKey: "missionControl.windowLabels"); updateSettings() }
    }
    private let detector = SpaceDetector()
    private let store = LabelStore()
    private var observer: AXObserver?
    private var dockElement: AXUIElement?
    private var dockPID: pid_t?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var openingUntil = Date.distantPast
    private var panels: [String: LabelPanel] = [:]
    private let notifications = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeExit", "AXExposeShowDesktop"]

    init() {
        let defaults = UserDefaults.standard
        desktopLabels = defaults.object(forKey: "missionControl.desktopLabels") as? Bool ?? true
        windowLabels = defaults.object(forKey: "missionControl.windowLabels") as? Bool ?? true
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.refreshPermission() } }
                .store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }.store(in: &subscriptions)
        refreshPermission()
    }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func refreshPermission() {
        trusted = AXIsProcessTrusted()
        guard trusted, desktopLabels || windowLabels else {
            stopObserving()
            status = trusted ? "F3 labels are off." : "Allow Accessibility to show labels in F3."
            return
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            stopObserving()
            status = "Waiting for Mission Control."
            return
        }
        if observer != nil, dockPID == dock.processIdentifier { return }
        stopObserving()
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        var newObserver: AXObserver?
        let result = AXObserverCreate(dock.processIdentifier, { _, _, notification, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<MissionControlLabels>.fromOpaque(context).takeUnretainedValue()
                owner.receive(notification as String)
            }
        }, &newObserver)
        guard result == .success, let newObserver else {
            status = "Mission Control notifications are unavailable on this macOS version."
            return
        }
        var registered = Set<String>()
        for name in notifications {
            if AXObserverAddNotification(newObserver, element, name as CFString,
                Unmanaged.passUnretained(self).toOpaque()) == .success { registered.insert(name) }
        }
        guard registered.contains("AXExposeShowAllWindows"), registered.contains("AXExposeExit") else {
            for name in registered { AXObserverRemoveNotification(newObserver, element, name as CFString) }
            status = "This macOS version doesn't expose the required Mission Control events."
            return
        }
        dockElement = element
        dockPID = dock.processIdentifier
        observer = newObserver
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        status = "Ready for F3."
    }

    private func updateSettings() {
        refreshPermission()
        if timer != nil { scan() }
    }

    private func receive(_ name: String) {
        if name == "AXExposeExit" || name == "AXExposeShowDesktop" { hide(); return }
        guard desktopLabels || windowLabels else { return }
        hide()
        openingUntil = Date().addingTimeInterval(2)
        // Track animation/hover geometry only while Mission Control is open. Idle has no timer.
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        scan()
    }

    private func stopObserving() {
        hide()
        if let observer, let dockElement {
            for name in notifications { AXObserverRemoveNotification(observer, dockElement, name as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        dockElement = nil
        dockPID = nil
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        panels.values.forEach { $0.orderOut(nil) }
    }

    private func scan() {
        guard AXIsProcessTrusted(), let dockElement else { refreshPermission(); return }
        guard let root = AXRead.find("mc", in: dockElement, depth: 3) else {
            panels.values.forEach { $0.orderOut(nil) }
            if Date() > openingUntil { hide() }
            return
        }
        let spaces = (try? detector.allSpaces()) ?? []
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var badges: [String: [PreviewBadge]] = [:]
        for display in AXRead.children(root) where AXRead.string(display, "AXIdentifier") == "mc.display" {
            let displayNumber = AXRead.value(display, "AXDisplayID") as? NSNumber
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == displayNumber
            }), let screenID = SpaceDetector.screenID(screen) else { continue }
            var items: [PreviewBadge] = []
            if desktopLabels, let list = AXRead.find("mc.spaces.list", in: display, depth: 3) {
                let buttons = AXRead.children(list).filter { AXRead.string($0, "AXRole") == "AXButton" }
                let displaySpaces = spaces.filter { $0.displayID == screenID || $0.displayID == "Main" }
                // Do not guess positions or mismatch names during a desktop add/remove transition.
                if buttons.count == displaySpaces.count {
                    for (button, space) in zip(buttons, displaySpaces) {
                        if let frame = AXRead.frame(button, primaryTop: primaryTop),
                           let badge = OverlayLayout.badgeFrame(in: frame, screen: screen.frame) {
                            items.append(PreviewBadge(frame: badge, title: store.label(for: space.id) ?? space.defaultName,
                                                      desktop: true))
                        }
                    }
                }
            }
            if windowLabels {
                var budget = 400
                AXRead.walkWindowPreviews(display, depth: 10, budget: &budget) { title, frame in
                    let converted = OverlayLayout.appKitFrame(frame, primaryTop: primaryTop)
                    if let badge = OverlayLayout.badgeFrame(in: converted, screen: screen.frame) {
                        items.append(PreviewBadge(frame: badge, title: title, desktop: false))
                    }
                }
            }
            badges[screenID] = items
            let panel = panels[screenID] ?? LabelPanel(screen: screen)
            panels[screenID] = panel
            panel.setFrame(screen.frame, display: false)
            panel.labels.badges = items.map {
                PreviewBadge(frame: $0.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
                             title: $0.title, desktop: $0.desktop)
            }
            if items.isEmpty { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }
        for (id, panel) in panels where badges[id] == nil { panel.orderOut(nil) }
        let desktopCount = badges.values.flatMap { $0 }.filter(\.desktop).count
        let windowCount = badges.values.flatMap { $0 }.filter { !$0.desktop }.count
        status = "F3: \(desktopCount) desktop labels, \(windowCount) window titles."
    }
}

@MainActor
private enum AXRead {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func string(_ element: AXUIElement, _ key: String) -> String? { value(element, key) as? String }
    static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, "AXChildren") as? [AXUIElement] ?? [] }
    static func find(_ identifier: String, in element: AXUIElement, depth: Int) -> AXUIElement? {
        if string(element, "AXIdentifier") == identifier { return element }
        guard depth > 0 else { return nil }
        for child in children(element).prefix(80) {
            if let result = find(identifier, in: child, depth: depth - 1) { return result }
        }
        return nil
    }
    static func rawFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, "AXPosition"), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, "AXSize"), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    static func frame(_ element: AXUIElement, primaryTop: CGFloat) -> CGRect? {
        rawFrame(element).map { OverlayLayout.appKitFrame($0, primaryTop: primaryTop) }
    }
    static func walkWindowPreviews(_ element: AXUIElement, depth: Int, budget: inout Int,
                                   found: (String, CGRect) -> Void) {
        guard depth > 0, budget > 0 else { return }
        budget -= 1
        let identifier = string(element, "AXIdentifier") ?? ""
        // Space thumbnails and the add/remove controls are handled independently.
        guard !identifier.hasPrefix("mc.spaces") else { return }
        let role = string(element, "AXRole")
        if role == "AXButton" || role == "AXImage" {
            let title = string(element, "AXTitle") ?? string(element, "AXDescription") ?? ""
            if !title.isEmpty, let frame = rawFrame(element), frame.width >= 80, frame.height >= 50 {
                found(title, frame)
                return
            }
        }
        for child in children(element) { walkWindowPreviews(child, depth: depth - 1, budget: &budget, found: found) }
    }
}

private struct PreviewBadge: Equatable {
    let frame: CGRect
    let title: String
    let desktop: Bool
}

@MainActor
private final class LabelPanel: NSPanel {
    let labels = LabelsView()
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = labels
        setAccessibilityElement(false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class LabelsView: NSView {
    var badges: [PreviewBadge] = [] {
        didSet { if oldValue != badges { needsDisplay = true } }
    }
    override func draw(_ dirtyRect: NSRect) {
        for badge in badges {
            NSColor.black.withAlphaComponent(0.88).setFill()
            NSBezierPath(roundedRect: badge.frame, xRadius: 6, yRadius: 6).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let font = NSFont.systemFont(ofSize: badge.desktop ? 12 : 11, weight: badge.desktop ? .semibold : .medium)
            (badge.title as NSString).draw(in: badge.frame.insetBy(dx: 6, dy: 4), withAttributes: [
                .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph
            ])
        }
    }
}
