import AppKit
import Combine
import ServiceManagement
import SpaceNameCore

@MainActor
final class SpaceModel: ObservableObject {
    @Published private(set) var current: Space?
    @Published private(set) var title = "SpaceNameBar"
    @Published private(set) var savedLabel = ""
    @Published private(set) var error: String?
    @Published private(set) var loginEnabled = false
    @Published var loginError: String?
    private let detector = SpaceDetector()
    private let store = LabelStore()
    private var subscriptions = Set<AnyCancellable>()
    private var settleTask: Task<Void, Never>?

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let events = [NSWorkspace.activeSpaceDidChangeNotification,
                      NSWorkspace.didWakeNotification,
                      NSWorkspace.sessionDidBecomeActiveNotification,
                      NSWorkspace.didActivateApplicationNotification]
        for name in events {
            workspace.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.handleChange() }
            }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.handleChange() }
            }.store(in: &subscriptions)
        refresh()
        refreshLoginStatus()
    }

    private func handleChange() {
        refresh()
        settleTask?.cancel()
        // One bounded follow-up per event handles WindowServer transition timing. No polling timer.
        settleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.refresh()
        }
    }

    func refresh(preferredDisplayID: String? = nil) {
        do {
            let snapshot = try detector.snapshot(preferredDisplayID: preferredDisplayID)
            current = snapshot.current
            savedLabel = store.label(for: snapshot.current.id) ?? ""
            title = savedLabel.isEmpty ? snapshot.current.defaultName : savedLabel
            error = nil
        } catch {
            current = nil
            savedLabel = ""
            title = "Space unavailable"
            self.error = error.localizedDescription
        }
    }

    func menuOpened() {
        settleTask?.cancel()
        refresh(preferredDisplayID: SpaceDetector.pointerDisplayID)
        refreshLoginStatus()
    }

    /// Verify the editor still refers to the visible desktop before writing anything.
    @discardableResult
    func save(_ text: String, expectedID: String?) -> Bool {
        let display = current?.displayID
        refresh(preferredDisplayID: display)
        guard let current, current.id == expectedID else { return false }
        store.set(text, for: current.id)
        refresh(preferredDisplayID: display)
        return true
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            if SMAppService.mainApp.status == .requiresApproval {
                loginError = "Allow SpaceNameBar in System Settings → General → Login Items & Extensions."
            }
        } catch {
            refreshLoginStatus()
            loginError = error.localizedDescription
        }
    }
}
