// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ghostcast",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GhostcastCore"),
        .executableTarget(name: "Ghostcast", dependencies: ["GhostcastCore"]),
        .testTarget(name: "GhostcastCoreTests", dependencies: ["GhostcastCore"]),
    ]
)
