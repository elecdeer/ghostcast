// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MirrorAudio",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MirrorAudioCore"),
        .executableTarget(name: "MirrorAudio", dependencies: ["MirrorAudioCore"]),
        .testTarget(name: "MirrorAudioCoreTests", dependencies: ["MirrorAudioCore"]),
    ]
)
