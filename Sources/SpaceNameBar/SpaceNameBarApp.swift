import AppKit
import SwiftUI
import SpaceNameCore
import ServiceManagement

@main
struct SpaceNameBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SpaceModel()

    var body: some Scene {
        MenuBarExtra {
            SpaceEditor(model: model, missionControl: delegate.missionControl, startup: delegate.startup)
        } label: {
            Text(model.title)
                .help(model.title)
                .accessibilityLabel("SpaceNameBar: \(model.title)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let startup = StartupController(autoStart: false)
    let missionControl = MissionControlLabels()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--check-layout-restoration") {
            Task { @MainActor in
                do { try await LayoutIntegrationChecks.run(); NSApp.terminate(nil) }
                catch { fputs("Layout integration check failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if CommandLine.arguments.contains("--watch-mission-control") {
            missionControl.start()
            return
        }
        if CommandLine.arguments.contains("--startup-status") || CommandLine.arguments.contains("--window-access-status") {
            print("Saved apps: \(startup.snapshot?.apps.count ?? 0)")
            print("Saved windows: \(startup.snapshot?.windows?.count ?? 0)")
            if let snapshot = startup.snapshot,
               let live = try? WindowLayout.inventory(bundleIDs: Set(snapshot.apps.map(\.bundleID))),
               let ids = try? SpaceDetector().managedSpaceIDs() {
                print("Readable live windows: \(live.count); fullscreen: \(live.filter(\.fullScreen).count)")
                print("Windows with recognized desktop: \(live.filter { !Set(ids.values).isDisjoint(with: $0.spaces) }.count)")
                for target in snapshot.spaces {
                    let planned = (snapshot.windows ?? []).filter { $0.bundleID == TerminalWindows.bundleID && $0.spaceID == target.id }.count
                    guard planned > 0, let id = ids[target.id] else { continue }
                    let actual = live.filter { $0.candidate.bundleID == TerminalWindows.bundleID && $0.spaces == [id] }
                    print("Desktop \(target.number): Terminal planned \(planned), actual \(actual.count), readable titles \(actual.filter { !$0.candidate.title.isEmpty }.count)")
                }
            }
            print("Backed-up custom names: \(startup.snapshot?.labels.count ?? 0)")
            print("Startup restore enabled: \(startup.enabled)")
            print("Login item enabled: \(SMAppService.mainApp.status == .enabled)")
            print("F3 Accessibility enabled: \(missionControl.trusted)")
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--check-window-placement") {
            Task { @MainActor in
                do {
                    let detector = SpaceDetector()
                    let spaces = try detector.allSpaces().filter { !$0.isFullScreen }
                    let ids = try detector.managedSpaceIDs()
                    guard spaces.count >= 2 else { throw WindowLayout.failure("Two ordinary desktops are required for this check.") }
                    let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 240, height: 100),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.title = "SpaceNameBar placement check"
                    window.orderFront(nil)
                    defer { window.close() }
                    try await Task.sleep(for: .milliseconds(500))
                    let id = UInt32(window.windowNumber)
                    let original = WindowLayout.membership(id)
                    guard original.count == 1, let home = original.first,
                          let target = spaces.compactMap({ ids[$0.id] }).first(where: { $0 != home }) else {
                        throw WindowLayout.failure("Could not identify test desktop destinations.")
                    }
                    try await WindowLayout.move(id, to: target)
                    try await WindowLayout.move(id, to: home)
                    print("PASS: disposable window moved to another desktop and back; both destinations verified.")
                    NSApp.terminate(nil)
                } catch { fputs("Placement check failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if CommandLine.arguments.contains("--save-startup") {
            do {
                try startup.captureAndEnable()
                UserDefaults.standard.synchronize()
                print(startup.status)
                print("Startup restore enabled: \(startup.enabled)")
                NSApp.terminate(nil)
            } catch {
                fputs("SpaceNameBar: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--configure-terminals"), CommandLine.arguments.count > index + 2 {
            do {
                guard let count = Int(CommandLine.arguments[index + 2]) else { throw StartupError.invalidSnapshot }
                try startup.setTerminalCount(count, spaceID: CommandLine.arguments[index + 1])
                print(startup.status)
                NSApp.terminate(nil)
            } catch { fputs("SpaceNameBar: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--verify-layout") {
            do {
                guard let snapshot = startup.snapshot else { throw StartupError.noSnapshot }
                let result = try LayoutRestorer.verify(snapshot)
                print("Windows verified on saved desktops: \(result.placed)/\(result.total)")
                NSApp.terminate(nil)
            } catch { fputs("SpaceNameBar: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--restore-layout") {
            startup.restoreNow()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                while startup.busy { try? await Task.sleep(for: .milliseconds(200)) }
                print(startup.status)
                NSApp.terminate(nil)
            }
            return
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--check-startup-launch"), CommandLine.arguments.count > index + 1 {
            let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                do {
                    try await StartupIntegrationChecks.run(fixtureURL: fixtureURL)
                    NSApp.terminate(nil)
                } catch {
                    fputs("Startup integration check failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        #endif
        if CommandLine.arguments.contains("--diagnose") {
            do {
                let snapshot = try SpaceDetector().snapshot()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot.spaces)
                print(String(decoding: data, as: UTF8.self))
                NSApp.terminate(nil)
            } catch {
                fputs("SpaceNameBar: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        // Start eagerly at login; opening the menu must never be required for restoration.
        missionControl.start()
        startup.start()
    }
}

private struct SpaceEditor: View {
    @ObservedObject var model: SpaceModel
    @ObservedObject var missionControl: MissionControlLabels
    @ObservedObject var startup: StartupController
    @State private var draft = ""
    @State private var editingID: String?
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool
    @State private var windowAccess = EditorWindowAccess()

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name this space").font(.headline)
                    Text(model.current?.defaultName ?? "SpaceNameBar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.menuOpened(); loadDraft() }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("e.g. 💬 Agent Runners", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Space name")
                        .focused($nameFocused)
                        .onSubmit(save)
                        .onChange(of: draft) { value in
                            if value.count > LabelStore.maximumLength {
                                draft = String(value.prefix(LabelStore.maximumLength))
                            }
                        }
                    Text("Give this desktop a little context.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Reset Name") {
                        if model.save("", expectedID: editingID) { windowAccess.close() }
                        else { changedSpace() }
                    }
                    .disabled(model.savedLabel.isEmpty)
                    Spacer()
                    Button("Save Name", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }

            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Mission Control (F3)").font(.subheadline.weight(.semibold))
                Toggle("Desktop names", isOn: $missionControl.desktopLabels)
                Toggle("Window titles", isOn: $missionControl.windowLabels)
                if !missionControl.trusted {
                    Text("Accessibility lets SpaceNameBar read thumbnail positions and window titles.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Enable Accessibility…") { missionControl.requestPermission() }
                } else {
                    Text(missionControl.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: {
                if !$0 { startup.setEnabled(false) }
                model.setLoginEnabled($0)
            }))
                .toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved startup layout").font(.subheadline.weight(.semibold))
                Toggle("Restore saved layout at login", isOn: Binding(get: { startup.enabled }, set: {
                    startup.setEnabled($0); model.refreshLoginStatus()
                }))
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(startup.snapshot == nil)
                HStack {
                    Button("Save current layout") { startup.saveCurrentApps(); model.refreshLoginStatus() }
                    Spacer()
                    Button("Restore saved layout") { startup.restoreNow() }
                        .disabled(startup.snapshot == nil || startup.busy)
                }
                Text(startup.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let current = model.current, !current.isFullScreen, startup.snapshot != nil {
                    Button("Save 2 Terminal windows for this desktop") {
                        do { try startup.setTerminalCount(2, spaceID: current.id) }
                        catch { saveError = error.localizedDescription }
                    }.disabled(startup.busy)
                }
                Text("Matching windows return to their saved desktops. Missing Terminal windows open fresh shells. Other apps restore their own documents; full-screen arrangements and running jobs may not return.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let loginError = model.loginError {
                Text(loginError).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("SpaceNameBar").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(20)
        }
        .frame(width: 380, height: 620)
        .background(EditorWindowReader(access: windowAccess, onOpen: { prepareEditor() }))
        .onAppear { prepareEditor() }
        .onChange(of: model.current?.id) { _ in loadDraft() }
    }

    private func prepareEditor() {
        model.menuOpened()
        missionControl.refreshPermission()
        loadDraft()
        nameFocused = true
    }

    private func loadDraft() {
        editingID = model.current?.id
        draft = model.savedLabel
        saveError = nil
    }

    private func changedSpace() {
        loadDraft()
        saveError = "The desktop changed. Enter a name for the current desktop."
    }

    private func save() {
        if model.save(draft, expectedID: editingID) { windowAccess.close() }
        else { changedSpace() }
    }
}

// MenuBarExtra caches its content. Observe its actual window so every reopening
// refreshes the editor, and dismiss that window using AppKit's public API.
@MainActor
private final class EditorWindowAccess {
    weak var window: NSWindow?
    func close() { window?.orderOut(nil) }
}

private struct EditorWindowReader: NSViewRepresentable {
    let access: EditorWindowAccess
    let onOpen: () -> Void

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.access = access
        view.onOpen = onOpen
        return view
    }

    func updateNSView(_ view: WindowObserverView, context: Context) {
        view.onOpen = onOpen
    }

    final class WindowObserverView: NSView {
        var access: EditorWindowAccess?
        var onOpen: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            access?.window = window
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(opened),
                    name: NSWindow.didBecomeKeyNotification, object: window)
            }
        }

        @objc private func opened() { onOpen?() }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
