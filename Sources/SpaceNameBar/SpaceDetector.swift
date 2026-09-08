import AppKit
import Darwin
import SpaceNameCore

enum DetectionError: LocalizedError {
    case unavailable, noSpaces, noActiveSpace
    var errorDescription: String? {
        switch self {
        case .unavailable: "This macOS version does not expose the Spaces information SpaceNameBar needs."
        case .noSpaces: "macOS hasn't returned its desktop list yet. Try again after switching desktops."
        case .noActiveSpace: "The active desktop could not be identified. Click this menu on the display you want to name."
        }
    }
}

@MainActor
final class SpaceDetector {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyDisplay = @convention(c) (Int32) -> Unmanaged<CFString>?
    private let handle: UnsafeMutableRawPointer?
    private let connection: Connection?
    private let copySpaces: CopySpaces?
    private let copyDisplay: CopyDisplay?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        self.handle = handle
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        connection = symbol("CGSMainConnectionID", as: Connection.self)
        copySpaces = symbol("CGSCopyManagedDisplaySpaces", as: CopySpaces.self)
        copyDisplay = symbol("CGSCopyActiveMenuBarDisplayIdentifier", as: CopyDisplay.self)
    }

    // Keep the framework loaded for the process lifetime; these function pointers must stay valid.
    func allSpaces() throws -> [Space] {
        guard let connection, let copySpaces else { throw DetectionError.unavailable }
        let cid = connection()
        guard let raw = copySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            throw DetectionError.noSpaces
        }
        let spaces = SpaceParser.parse(raw)
        guard !spaces.isEmpty else { throw DetectionError.noSpaces }
        return spaces
    }

    func snapshot(preferredDisplayID: String? = nil) throws -> (spaces: [Space], current: Space) {
        let spaces = try allSpaces()
        guard let connection else { throw DetectionError.unavailable }
        let cid = connection()
        let activeDisplay = copyDisplay?(cid)?.takeRetainedValue() as String?
        let display = preferredDisplayID ?? activeDisplay ?? Self.screenID(NSScreen.main)
        guard let current = SpaceParser.current(in: spaces, displayID: display) else {
            throw DetectionError.noActiveSpace
        }
        return (spaces, current)
    }

    static func screenID(_ screen: NSScreen?) -> String? {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var pointerDisplayID: String? {
        screenID(NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
    }
}
