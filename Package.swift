// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioManager",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "AudioManager",
            path: "Sources/AudioManager"
        )
    ]
)
