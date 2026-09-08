import AppKit
import SwiftUI
import SpaceNameCore

@main
struct SpaceNameBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SpaceModel()
    @StateObject private var missionControl = MissionControlLabels()

    var body: some Scene {
        MenuBarExtra {
            SpaceEditor(model: model, missionControl: missionControl)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        }
    }
}

private struct SpaceEditor: View {
    @ObservedObject var model: SpaceModel
    @ObservedObject var missionControl: MissionControlLabels
    @State private var draft = ""
    @State private var editingID: String?
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool
    @State private var windowAccess = EditorWindowAccess()

    var body: some View {
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
            Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                .toggleStyle(.switch).controlSize(.small)
            Text("Starts SpaceNameBar. Does not restore other apps or windows.")
                .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 340)
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
