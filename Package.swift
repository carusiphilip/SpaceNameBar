// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceNameBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SpaceNameBar", targets: ["SpaceNameBar"])],
    targets: [
        .target(name: "SpaceNameCore"),
        .target(name: "WindowSpaceBridge", linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]),
        .executableTarget(name: "SpaceNameBar", dependencies: ["SpaceNameCore", "WindowSpaceBridge"]),
        // A standalone test runner also works with Apple's Command Line Tools (no Xcode/XCTest needed).
        .executableTarget(name: "SpaceNameCoreChecks", dependencies: ["SpaceNameCore"], path: "Tests/SpaceNameCoreTests")
    ]
)
