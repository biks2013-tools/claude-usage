// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: the usage response, the credentials' public fields, formatting. No AppKit.
        .target(name: "UsageCore"),
        // The menu bar app: status item, menu, Keychain, network.
        // SkyLight: read-only Space queries (which desktop a window is on, the current one).
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: ["UsageCore"],
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("SkyLight"),
            ]
        ),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
